import Foundation
import SwiftUI

struct ChatMessage: Identifiable {
    enum Role { case user, agent, system, step }
    /// Lifecycle of a `.step` message (a build/apply/format/commit stage).
    enum StepState { case running, ok, failed }
    let id = UUID()
    let role: Role
    /// For most roles this is the message body; for `.step` it's the step title.
    var text: String
    /// `.step` only: the stage's own console output, shown in its embedded
    /// terminal so each stage's log stands alone instead of pooling into one.
    var lines: [String] = []
    /// `.step` only.
    var state: StepState = .running
    /// Present when the user selected a bundled recipe. The agent receives the
    /// full Markdown body while the transcript renders a rich recipe card.
    var recipe: Recipe? = nil
}

/// A user-authored request waiting for the current chat operation to finish.
/// Queued prompts stay local to the conversation so they can be corrected or
/// removed before an agent receives them.
struct QueuedChatMessage: Identifiable {
    let id = UUID()
    var text: String
}

enum Phase: String {
    case checking = "Checking environment…"
    case needsNix = "Nix not installed"
    case needsConfig = "No configuration yet"
    case ready = "Ready"
}

extension Notification.Name {
    /// Posted with `userInfo["id"]` set to a recipe's front-matter id when a
    /// `nixmc://recipe/<id>` deep link is opened. Observed by `AppState`.
    static let openRecipe = Notification.Name("nixmc.openRecipe")
}

@MainActor
final class AppState: ObservableObject {
    let paths = Paths()
    /// User-tunable behavior (Settings window, ⌘,). Read at the moment of
    /// use so changes apply to the very next operation.
    let settings = AppSettings.shared

    @Published var phase: Phase = .checking
    @Published var busy = false
    /// Human label of the operation currently running (drives the status line).
    @Published var activity = ""
    @Published var log: [String] = []
    @Published var transcript: [ChatMessage] = []
    @Published var queuedMessages: [QueuedChatMessage] = []
    @Published var commits: [Git.Commit] = []
    /// Cached AI summary for each commit's diff, keyed by commit id — populated
    /// lazily (cache-only, no agent calls) alongside `commits`, and used to
    /// power the global search over history.
    @Published var commitSummaries: [String: String] = [:]
    @Published var agents: [AgentCLI] = []
    @Published var selectedAgent: AgentCLI?

    /// Homebrew apps (casks) and CLI tools (brews) declared by the config,
    /// surfaced as clickable sidebar sections. Read from `.nixmc/homebrew/data.json`.
    @Published var casks: [String] = []
    @Published var brews: [String] = []

    /// Commit whose diff is being viewed (drives the diff sheet).
    @Published var diffCommit: Git.Commit?
    @Published var diffText: String = ""

    /// Uncommitted edits (the agent's work) awaiting build + Apply.
    @Published var pending = false
    /// True after a successful build — Apply is safe to offer.
    @Published var buildOK = false
    /// True after a failed build — offer to hand the error to the agent.
    @Published var buildFailed = false
    @Published var showWorkingDiff = false
    @Published var workingDiffText = ""
    /// Drives the prompt-templates gallery sheet.
    @Published var showTemplates = false

    /// A recipe requested via a `nixmc://recipe/<id>` deep link. ContentView
    /// surfaces it as a preview sheet and resets this to nil once shown.
    @Published var deepLinkedRecipe: Recipe?
    private var deepLinkObserver: NSObjectProtocol?

    /// Agent-generated guide to what the current config actually does,
    /// keyed by section id (`ConfigGuide.sectionIDs`). Loaded lazily the
    /// first time the Help pane is shown.
    @Published var helpGuide: [String: String] = [:]
    @Published var helpGuideLoading = false
    @Published var helpGuideError: String?
    /// Recipe documentation to add to GUIDE.md at the next successful apply.
    private var pendingRecipeGuide: Recipe?

    /// Explicit font scales for the generated guide. `DynamicTypeSize` does
    /// not reliably resize custom Markdown fonts on macOS, so the renderer
    /// consumes this multiplier directly.
    private static let helpTextScales: [CGFloat] = [0.85, 1, 1.15, 1.3, 1.5, 1.75]

    @Published var helpTextScaleIndex = UserDefaults.standard.object(forKey: "helpTextScaleIndex") == nil
        ? 1
        : UserDefaults.standard.integer(forKey: "helpTextScaleIndex") {
        didSet { UserDefaults.standard.set(helpTextScaleIndex, forKey: "helpTextScaleIndex") }
    }

    var helpTextScale: CGFloat {
        AppState.helpTextScales[min(max(helpTextScaleIndex, 0), AppState.helpTextScales.count - 1)]
    }

    func increaseHelpTextSize() {
        helpTextScaleIndex = min(helpTextScaleIndex + 1, AppState.helpTextScales.count - 1)
    }

    func decreaseHelpTextSize() {
        helpTextScaleIndex = max(helpTextScaleIndex - 1, 0)
    }

    func resetHelpTextSize() {
        helpTextScaleIndex = 1
    }

    /// AI-generated plain-English description of the diff currently on screen,
    /// and whether the selected agent is still producing it. Shared by both diff sheets
    /// (only one is open at a time). `nil` = none yet.
    @Published var summary: String?
    @Published var summarizing = false
    /// The diff the summary belongs to (used for regenerate / cache lookups).
    private var summaryDiff = ""

    /// Weekly flake-update proposals (Updates sidebar section).
    @Published var proposals: [UpdateProposal] = []
    @Published var lastUpdateCheck: Date?
    @Published var updateChecking = false
    /// Proposal shown in the detail pane (nil = none).
    @Published var selectedProposalID: String?
    @Published var proposalDiffText = ""
    /// Apply-time failure (cherry-pick conflict) surfaced in the proposal pane.
    @Published var proposalActionError: String?
    var selectedProposal: UpdateProposal? { proposals.first { $0.id == selectedProposalID } }
    private let updateScheduler = UpdateScheduler()
    private var schedulerStarted = false
    private var updatesStoreLoaded = false

    /// A newer nixmc release than the running app (nil = up to date).
    @Published var appUpdate: SelfUpdater.Release?
    /// True while downloading/installing the app update.
    @Published var appUpdating = false
    @Published var appUpdateError: String?
    private var selfUpdateCheckedAtLaunch = false
    var isUpdateDue: Bool {
        lastUpdateCheck.map { Date.now.timeIntervalSince($0) >= settings.updateCadence.seconds } ?? true
    }

    /// PID of the currently streaming child (agent or build), for cancellation.
    private var currentPID: Int32? { didSet { canStop = currentPID != nil } }
    /// True while a stoppable child (agent or build) is running.
    @Published var canStop = false
    /// The user asked to stop the running task.
    private var stopped = false
    /// Console output captured from the most recent build (for the Fix prompt).
    private var lastBuildOutput: [String] = []

    @Published var host = Paths.hostName()

    init() {
        // Resolve `nixmc://recipe/<id>` deep links (posted by AppDelegate) to a
        // concrete recipe. ContentView presents it once the main window exists.
        deepLinkObserver = NotificationCenter.default.addObserver(
            forName: .openRecipe, object: nil, queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, let id = note.userInfo?["id"] as? String else { return }
                self.deepLinkedRecipe = RecipeCatalog.recipe(withID: id)
            }
        }
    }

    deinit {
        if let deepLinkObserver { NotificationCenter.default.removeObserver(deepLinkObserver) }
    }

    // MARK: status line

    enum StatusKind { case idle, working, attention, error }

    /// The single most important state to surface while nixmc is running as a
    /// menu-bar app. The order here is deliberate: active work takes priority
    /// over work waiting for review, which in turn takes priority over an
    /// available update proposal.
    enum MenuBarStatus: Equatable {
        case idle
        case working
        case reviewNeeded
        case updateAvailable
        case attentionNeeded

        var symbolName: String {
            switch self {
            case .idle: "cube.transparent"
            case .working: "arrow.triangle.2.circlepath"
            case .reviewNeeded: "exclamationmark.circle.fill"
            case .updateAvailable: "arrow.down.circle.fill"
            case .attentionNeeded: "exclamationmark.triangle.fill"
            }
        }

        var label: String {
            switch self {
            case .idle: "nixmc is ready"
            case .working: "nixmc is working"
            case .reviewNeeded: "Changes need review"
            case .updateAvailable: "Updates are ready to review"
            case .attentionNeeded: "nixmc needs attention"
            }
        }
    }

    /// What the sidebar status should say, given everything that has happened.
    var statusText: String {
        if busy { return activity.isEmpty ? "Working…" : activity }
        if phase != .ready { return phase.rawValue }
        if buildFailed { return "Build failed" }
        if pending && buildOK { return "Ready to apply" }
        if pending { return "Uncommitted changes" }
        return "Ready"
    }

    var statusKind: StatusKind {
        if busy { return .working }
        if phase != .ready { return .attention }
        if buildFailed { return .error }
        if pending { return .attention }
        return .idle
    }

    var menuBarStatus: MenuBarStatus {
        if busy || updateChecking { return .working }
        if buildFailed || pending { return .reviewNeeded }
        if !proposals.isEmpty || appUpdate != nil { return .updateAvailable }
        if phase != .ready { return .attentionNeeded }
        return .idle
    }

    // MARK: environment

    func refresh() {
        agents = AgentCLI.detected()
        if selectedAgent == nil || !agents.contains(where: { $0.id == selectedAgent?.id }) {
            selectedAgent = agents.first { $0.id == settings.preferredAgentID } ?? agents.first
        }
        if let selectedAgent, settings.preferredAgentID != selectedAgent.id {
            settings.preferredAgentID = selectedAgent.id
        }
        if !NixInstaller.isInstalled {
            phase = .needsNix
        } else if !ConfigScaffold.exists(repoDir: paths.repoDir) {
            phase = .needsConfig
        } else {
            phase = .ready
            out("Using configuration at \(paths.repoDir.path)")
            reloadCommits()
            loadHomebrew()
            loadUpdatesStore()
            startUpdateSchedulerIfNeeded()
            checkForAppUpdateAtLaunch()
            pending = Git.hasChanges(in: paths.repoDir)
            // Resolve the actual flake attribute (may differ from the host name).
            let fallback = host
            Task.detached {
                let name = Paths.flakeConfigName(fallback: fallback)
                await MainActor.run {
                    if name != self.host {
                        self.host = name
                        self.out("Flake configuration: \(name)")
                    }
                }
            }
        }
    }

    /// Select an agent for this session and remember it as the preferred one.
    func selectAgent(id: String) {
        let changed = selectedAgent?.id != id
        settings.preferredAgentID = id
        guard let match = agents.first(where: { $0.id == id }) else { return }
        selectedAgent = match
        if changed {
            summary = nil
            helpGuide = [:]
            commitSummaries = [:]
            reloadCommits()
        }
    }

    func reloadCommits() {
        let repo = paths.repoDir
        Task {
            let list = await Task.detached { Git.log(in: repo) }.value
            self.commits = list
            // Best-effort: pick up any already-cached AI summaries for these
            // commits (cache-only lookup, no agent calls) so search can match
            // against them without paying to (re)generate anything.
            let map = await Task.detached { () -> [String: String] in
                var map: [String: String] = [:]
                for c in list {
                    let diff = Git.show(c.id, in: repo)
                    if let s = Summarizer.cached(for: diff) { map[c.id] = s }
                }
                return map
            }.value
            self.commitSummaries = map
        }
    }

    /// Reload the Homebrew lists shown in the sidebar (the agent may have edited
    /// `data.json`). Best-effort, off the main thread.
    func loadHomebrew() {
        let url = paths.homebrewData
        Task.detached {
            let hb = (try? HomebrewData.load(from: url)) ?? HomebrewData()
            await MainActor.run { self.casks = hb.casks; self.brews = hb.brews }
        }
    }

    /// Cap on retained log lines — unbounded growth is what made the terminal
    /// view sluggish during long builds/activations (thousands of lines kept
    /// alive, each re-diffed by SwiftUI on every append).
    private static let maxLogLines = 2000

    private func out(_ line: String) {
        log.append(line)
        if log.count > Self.maxLogLines { log.removeFirst(log.count - Self.maxLogLines) }
    }

    // MARK: pipeline steps
    //
    // Each stage of the build → apply → format → commit pipeline is its own chat
    // entry with a self-contained terminal, rather than every stage pouring into
    // one shared log. `beginStep` appends a running step and returns its
    // transcript index; `stepOut` streams a line into it; `finishStep` marks it.

    @discardableResult
    private func beginStep(_ title: String) -> Int {
        transcript.append(ChatMessage(role: .step, text: title))
        return transcript.count - 1
    }

    private func stepOut(_ index: Int, _ line: String) {
        guard transcript.indices.contains(index) else { return }
        transcript[index].lines.append(line)
        let over = transcript[index].lines.count - Self.maxLogLines
        if over > 0 { transcript[index].lines.removeFirst(over) }
    }

    private func finishStep(_ index: Int, ok: Bool) {
        guard transcript.indices.contains(index) else { return }
        transcript[index].state = ok ? .ok : .failed
    }

    /// A finished apply does not need to leave a stack of successful terminal
    /// cards in the conversation. Failures stay visible for diagnosis.
    private func removeSuccessfulPipelineSteps() {
        transcript.removeAll { $0.role == .step && $0.state == .ok }
    }

    // MARK: bootstrap

    func createConfig() {
        guard ConfigScaffold.canCreate(repoDir: paths.repoDir) else {
            out("A configuration or other files already exist at \(paths.repoDir.path). NixMC will not overwrite them.")
            return
        }
        run {
            do {
                self.out("Scaffolding configuration at \(self.paths.repoDir.path)…")
                try FileManager.default.createDirectory(at: self.paths.repoDir, withIntermediateDirectories: true)
                try ConfigScaffold.create(repoDir: self.paths.repoDir)
                self.out("Linking \(Paths.canonicalConfigDir) → repo (may prompt for admin)…")
                try CanonicalConfig.ensureLink(repoDir: self.paths.repoDir)
                self.out("Configuration ready.")
            } catch {
                self.out("Setup failed: \(error.localizedDescription)")
            }
            self.refresh()
        }
    }

    /// Start over without deleting the existing configuration: archive it
    /// beside the managed repo and create the embedded template in its place.
    func replaceConfigWithTemplate() {
        run {
            let repo = self.paths.repoDir
            do {
                self.out("Archiving the current configuration…")
                let backup = try ConfigScaffold.replaceWithTemplate(repoDir: repo)
                if backup != repo {
                    self.out("Previous configuration moved to \(backup.path)")
                }
                self.out("Scaffolding a fresh configuration at \(repo.path)…")
                try CanonicalConfig.ensureLink(repoDir: repo)
                self.out("Fresh configuration ready.")
            } catch {
                self.out("Could not start from scratch: \(error.localizedDescription)")
            }
            self.refresh()
        }
    }

    /// Clone an existing nix-darwin repository into nixmc's managed location,
    /// then make it the canonical configuration. Existing local files are
    /// deliberately never overwritten during bootstrap.
    func importConfig(remote input: String) {
        let remote = Git.normalizeRemote(input, ssh: false)
        guard !remote.isEmpty else {
            out("Enter a Git repository URL first.")
            return
        }

        run {
            let repo = self.paths.repoDir
            self.out("Cloning configuration from \(remote)…")
            let cloneError: String? = await Task.detached {
                let manager = FileManager.default
                do {
                    if manager.fileExists(atPath: repo.path) {
                        let contents = try manager.contentsOfDirectory(atPath: repo.path)
                            .filter { $0 != ".DS_Store" }
                        guard contents.isEmpty else {
                            return "\(repo.path) is not empty. Move its contents before importing a remote configuration."
                        }
                    } else {
                        try manager.createDirectory(at: repo.deletingLastPathComponent(), withIntermediateDirectories: true)
                    }

                    let result = try Shell.run("/usr/bin/git", ["clone", "--depth", "1", remote, repo.path])
                    guard result.ok else {
                        return result.stderr.isEmpty ? result.stdout : result.stderr
                    }
                    guard ConfigScaffold.exists(repoDir: repo) else {
                        return "The cloned repository does not contain a flake.nix file."
                    }
                    return nil
                } catch {
                    return error.localizedDescription
                }
            }.value

            if let cloneError {
                self.out("Remote configuration import failed: \(cloneError.trimmingCharacters(in: .whitespacesAndNewlines))")
                return
            }

            do {
                self.out("Linking \(Paths.canonicalConfigDir) → imported configuration (may prompt for admin)…")
                try CanonicalConfig.ensureLink(repoDir: repo)
                self.out("Remote configuration ready.")
            } catch {
                self.out("Remote configuration imported, but linking failed: \(error.localizedDescription)")
            }
            self.refresh()
        }
    }

    // MARK: the loop

    /// Facts the app already knows, handed to the agent up front so it doesn't
    /// waste turns rediscovering the repo layout / host / where things live.
    /// Kept short and stable — enough to orient, not a full map.
    private var agentContext: String {
        let dir = paths.repoDir.path
        let user = Paths.userName()
        var context = """
        You are editing the nix-darwin configuration at \(dir). Use these facts \
        instead of rediscovering them:
        - This is a nix-darwin + Home Manager flake. Build attribute: \(host) \
        (i.e. `darwin-rebuild switch --flake \(dir)#\(host)`). Host name: \
        \(Paths.hostName()); primary user: \(user).
        - Inspect `flake.nix` and its imports before editing. The nixmc starter \
        template has a module for each Configure section: `modules/darwin/` \
        contains `packages.nix`, `fonts.nix`, `macos-settings.nix`, \
        `services.nix`, and `security-secrets.nix`; `modules/home/` contains \
        `shell-environment.nix` and `ai-agents.nix`. Imported configurations \
        may use a different module layout; edit only files the existing flake \
        actually imports.
        - AI-agent recipes are scoped to `modules/home/ai-agents.nix` only. Do \
        not put AI-agent settings, services, packages, or launch agents in any \
        other module when processing one of those recipes.
        - Homebrew apps and CLI tools are declared in \
        `.nixmc/homebrew/data.json` (JSON keys "brews", "casks", "taps"), NOT in \
        nix files — edit that JSON to add/remove Homebrew packages. Treat cask strings \
        as exact Homebrew identifiers: preserve existing slugs and use the user-provided \
        slug verbatim rather than guessing from an app's display name.
        - After you finish, the app builds and validates the flake and shows the \
        user a diff. Do NOT run `darwin-rebuild`, `nix build`, or `nix eval` \
        yourself — just make the edits.
        - Do not edit `GUIDE.md` or `.nixmc/recipe-guides/`. Recipe guide text is
        human-authored and NixMC copies it verbatim into its local guide-fragment
        store, then assembles the final tracked `GUIDE.md` after a successful
        recipe apply.
        - Recipe-authoring skill: when asked to create or share a recipe, author
        a self-contained Markdown recipe rather than applying the change directly.
        Use YAML front matter with `id`, `title`, `section`, `symbol`, `summary`,
        `featured`, and a primary `source`; follow it with a concrete,
        implementation-oriented body. Choose one of NixMC's Configure section
        names exactly. Verify Nix attributes and macOS options first, avoid
        machine-specific paths or secrets, and add a `## Guide` section only when
        the user supplies or explicitly approves human-authored documentation.
        Do not generate, rewrite, or summarize that guide text. Save a requested
        shared recipe in the configured team recipe repository when available;
        otherwise return the complete Markdown for the user to place there.
        - MCP-NixOS is available as the `nixos` server. Before adding or changing \
        a Nix package, flake input, nix-darwin option, or Home Manager option, \
        use its `nix` tool to verify the exact attribute or option. Use \
        `nix_versions` when the requested package version matters. Do not guess \
        Nix names or options when the MCP result is available.
        """
        let extra = settings.customInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if !extra.isEmpty {
            context += "\n\nUser preferences (follow them when they apply):\n\(extra)"
        }
        return context
    }

    /// The CLIs run one-shot sessions, so supply a small amount of completed
    /// dialogue to make follow-ups such as "1" or "do that" meaningful. Step
    /// logs and system notices are intentionally omitted: they add noise and
    /// do not help resolve conversational references.
    private func recentConversationContext() -> String {
        let messages = transcript
            .filter { ($0.role == .user || $0.role == .agent) && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .suffix(6)
        guard !messages.isEmpty else { return "" }

        let turns = messages.map { message -> String in
            let role = message.role == .user ? "User" : "Agent"
            let body = truncatedConversationText(message.text, limit: 4_000)
            return "\(role):\n\(body)"
        }
        return """

        Conversation context (use it only to resolve references in the current request):
        \(turns.joined(separator: "\n\n"))
        """
    }

    private func truncatedConversationText(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.suffix(limit)) + "\n[earlier text omitted]"
    }

    /// `prompt` is what the agent receives; `display` is the shorter text shown
    /// in the chat bubble (defaults to the prompt itself).
    func send(_ prompt: String, display: String? = nil, recipe: Recipe? = nil) {
        guard let agent = selectedAgent else {
            out("No agent CLI detected. Install Claude Code or Codex CLI.")
            return
        }
        buildFailed = false
        buildOK = false
        stopped = false
        activity = "Agent working…"
        // Capture history before adding the current bubble; the current prompt
        // is sent separately and should remain the source of truth.
        let conversationContext = recentConversationContext()
        transcript.append(ChatMessage(role: .user, text: display ?? prompt, recipe: recipe))
        let agentMessage = ChatMessage(role: .agent, text: "")
        transcript.append(agentMessage)
        let agentMessageID = agentMessage.id
        let fullPrompt = "\(agentContext)\(conversationContext)\n\nCurrent request:\n\(prompt)"
        run {
            let ok = await agent.run(prompt: fullPrompt, cwd: self.paths.repoDir,
                                     onSpawn: { pid in Task { @MainActor in self.currentPID = pid } }) { line in
                Task { @MainActor in
                    guard let index = self.transcript.firstIndex(where: { $0.id == agentMessageID }) else { return }
                    self.transcript[index].text += line + "\n"
                }
            }
            self.currentPID = nil
            if self.stopped {
                self.transcript.append(ChatMessage(role: .system, text: "Stopped."))
                return
            }
            let repo = self.paths.repoDir
            self.pending = await Task.detached { Git.hasChanges(in: repo) }.value
            if self.pending, let recipe, recipe.guide != nil {
                self.pendingRecipeGuide = recipe
            }
            if ok && self.pending && self.settings.autoFormat {
                // Tidy only after the agent has actually changed the config.
                await self.formatStep()
                self.pending = await Task.detached { Git.hasChanges(in: repo) }.value
            }
            self.loadHomebrew()
            if !ok {
                self.transcript.append(ChatMessage(role: .system, text: "Agent exited with an error."))
            }
            if ok {
                if !self.pending {
                    self.transcript.append(ChatMessage(role: .system,
                        text: "No configuration changes were made. Nothing to build or apply."))
                } else if self.settings.autoBuild {
                    await self.buildThenOfferApply(reason: prompt)
                } else {
                    self.transcript.append(ChatMessage(role: .system,
                        text: "Edits ready. Review the diff, then Build & Apply."))
                }
            }
        }
    }

    /// Add a request for delivery after the current agent/build operation.
    func enqueue(_ prompt: String) {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        queuedMessages.append(QueuedChatMessage(text: text))
    }

    func updateQueuedMessage(_ id: UUID, text: String) {
        guard let index = queuedMessages.firstIndex(where: { $0.id == id }) else { return }
        queuedMessages[index].text = text
    }

    func removeQueuedMessage(_ id: UUID) {
        queuedMessages.removeAll { $0.id == id }
    }

    /// Resume delivery after the user cancelled a running chat operation.
    func resumeQueuedMessages() {
        stopped = false
        sendNextQueuedMessageIfPossible()
    }

    private func sendNextQueuedMessageIfPossible() {
        guard !busy, !stopped, selectedAgent != nil, !queuedMessages.isEmpty else { return }
        let next = queuedMessages.removeFirst()
        guard !next.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            sendNextQueuedMessageIfPossible()
            return
        }
        send(next.text)
    }

    private func buildThenOfferApply(reason: String) async {
        activity = "Building…"
        let step = beginStep("Build configuration")
        let ok = await runBuild { self.stepOut(step, $0) }
        finishStep(step, ok: ok && !stopped)
        if stopped {
            transcript.append(ChatMessage(role: .system, text: "Build stopped."))
            return
        }
        buildOK = ok
        buildFailed = !ok
        transcript.append(ChatMessage(role: .system,
            text: ok ? "Build succeeded. Review the diff, then Apply." : "Build failed. Use “Fix with agent” to hand it the error."))
    }

    /// Run `darwin-rebuild build`, capturing its output for the Fix prompt and
    /// streaming each line to `sink` (the owning step's terminal).
    private func runBuild(sink: @escaping (String) -> Void) async -> Bool {
        lastBuildOutput = []
        let ok = await DarwinRebuild.build(
            host: host,
            onSpawn: { pid in Task { @MainActor in self.currentPID = pid } }
        ) { line in
            Task { @MainActor in
                self.lastBuildOutput.append(line)
                sink(line)
            }
        }
        currentPID = nil
        return ok
    }

    /// Run the nix formatter as its own pipeline step (own terminal). Best-effort
    /// — no-ops with a "no formatter found" line when none is installed.
    private func formatStep() async {
        activity = "Formatting…"
        let step = beginStep("Format")
        await NixFormat.run(repoDir: paths.repoDir) { line in
            Task { @MainActor in self.stepOut(step, line) }
        }
        finishStep(step, ok: true)
    }

    /// After a successful `darwin-rebuild switch`, hand the console output to
    /// the agent so it can catch anything worth reflecting in the config —
    /// Homebrew renaming/adopting a cask, a deprecation notice, and the like.
    /// The agent's read-through appears as its own chat message; any edit it
    /// makes lands in the same commit as the change that triggered it. A no-op
    /// when there's no agent or output.
    private func reviewApplyOutput(_ output: [String]) async {
        guard let agent = selectedAgent, !output.isEmpty else { return }
        activity = "Reviewing apply output…"
        let prompt = """
        You just ran `darwin-rebuild switch` for this nix-darwin configuration. \
        Below is the console output. Skim it for anything actionable that should \
        be reflected in the config files — e.g. a Homebrew cask or formula that \
        was renamed, adopted, or deprecated, or a warning implying an option \
        changed. If you find something concrete, make the matching edit. If \
        nothing in the output warrants a change, make no edits.

        ```
        \(output.suffix(200).joined(separator: "\n"))
        ```
        """
        transcript.append(ChatMessage(role: .agent, text: ""))
        let idx = transcript.count - 1
        _ = await agent.run(prompt: prompt, cwd: paths.repoDir,
                            onSpawn: { pid in Task { @MainActor in self.currentPID = pid } }) { line in
            Task { @MainActor in self.transcript[idx].text += line + "\n" }
        }
        currentPID = nil
    }

    /// Kill the currently running agent or build.
    func stop() {
        guard let pid = currentPID else { return }
        stopped = true
        activity = "Stopping…"
        out("Stopping (pid \(pid))…")
        let target = pid
        Task.detached { Shell.interruptTree(target) }
    }

    /// Discard only the visible conversation. Pending config edits and their
    /// build state remain available through the review bar and History.
    func clearConversation() {
        guard !busy else { return }
        transcript.removeAll()
    }

    /// Hand the actual build console output back to the agent to repair.
    func fixBuild() {
        // Prefer the captured build output; fall back to the visible log tail.
        let captured = lastBuildOutput.isEmpty ? Array(log.suffix(80)) : lastBuildOutput
        let errors = captured.suffix(120).joined(separator: "\n")
        let prompt = """
        The nix-darwin configuration failed to build. Diagnose and fix the config \
        so that `darwin-rebuild build` succeeds. Do not change unrelated things. \
        Here is the exact console output from the failed build:

        ```
        \(errors)
        ```
        """
        send(prompt, display: "Fix the build error")
    }

    /// Throw away the uncommitted changes. Stashes rather than hard-resets, so
    /// a mistaken drop can still be recovered with `git stash pop` in the repo.
    func dropChanges() {
        run {
            let repo = self.paths.repoDir
            self.activity = "Dropping changes…"
            let step = self.beginStep("Drop changes")
            self.stepOut(step, "› git stash push --include-untracked")
            let error: String? = await Task.detached {
                do { try Git.stashChanges(in: repo); return nil }
                catch { return error.localizedDescription }
            }.value
            if let error {
                self.stepOut(step, error)
                self.finishStep(step, ok: false)
                self.transcript.append(ChatMessage(role: .system,
                    text: "Couldn't drop the changes — see the step log above."))
                return
            }
            self.stepOut(step, "Dropped (recoverable with `git stash pop`).")
            self.finishStep(step, ok: true)
            self.pending = await Task.detached { Git.hasChanges(in: repo) }.value
            self.buildOK = false
            self.buildFailed = false
            self.showWorkingDiff = false
            self.workingDiffText = ""
            self.loadHomebrew()
            self.transcript.append(ChatMessage(role: .system,
                text: "Dropped the uncommitted changes. They're stashed in git if you change your mind."))
        }
    }

    /// Load the working diff (agent's uncommitted edits) into the viewer.
    func reviewChanges() {
        workingDiffText = "Loading…"
        showWorkingDiff = true
        resetSummary()
        let repo = paths.repoDir
        Task.detached {
            let text = Git.workingDiff(in: repo)
            await MainActor.run {
                self.workingDiffText = text
                self.loadSummary(for: text)
            }
        }
    }

    // MARK: change summary

    private func resetSummary() {
        summary = nil
        summarizing = false
        summaryDiff = ""
    }

    /// Show a cached summary immediately if we have one; otherwise ask the selected agent.
    /// No-op (the sheet shows just the raw diff) when AI summaries are off.
    func loadSummary(for diff: String, force: Bool = false) {
        guard settings.aiSummaries else {
            summary = nil
            summarizing = false
            return
        }
        let trimmed = diff.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "Loading…" else { return }
        summaryDiff = diff
        if !force, let hit = Summarizer.cached(for: diff) {
            summary = hit
            summarizing = false
            return
        }
        summarizing = true
        summary = nil
        let repo = paths.repoDir
        Task.detached {
            let text = await Summarizer.summarize(diff, cwd: repo, force: force)
            await MainActor.run {
                // Ignore if the on-screen diff changed while we were working.
                guard diff == self.summaryDiff else { return }
                self.summary = text ?? "Couldn't generate a summary with the selected agent."
                self.summarizing = false
            }
        }
    }

    /// Re-run the selected agent for the current diff, ignoring the cache.
    func regenerateSummary() { loadSummary(for: summaryDiff, force: true) }

    // MARK: global search

    struct ChangeSearchResult: Identifiable {
        let id: String
        let commit: Git.Commit
        let snippet: String
    }

    struct HelpSearchResult: Identifiable {
        let id: String
        let sectionID: String
        let snippet: String
    }

    /// Generates the help guide the first time a search actually needs it, so
    /// opening the search field before ever visiting a Configure area still
    /// finds matches instead of coming up empty.
    func ensureSearchIndexed() {
        if helpGuide.isEmpty && !helpGuideLoading { loadHelpGuide() }
    }

    /// Search commit history (subject + any already-cached AI summary) and the
    /// agent-generated config guide, sectioned the same way results are shown.
    func search(_ query: String) -> (changes: [ChangeSearchResult], help: [HelpSearchResult]) {
        guard !query.isEmpty else { return ([], []) }
        let changes: [ChangeSearchResult] = commits.compactMap { c in
            let summary = commitSummaries[c.id] ?? ""
            let haystack = summary.isEmpty ? c.subject : "\(c.subject)\n\(summary)"
            guard let snippet = Self.searchSnippet(in: haystack, matching: query) else { return nil }
            return ChangeSearchResult(id: c.id, commit: c, snippet: snippet)
        }
        // "Overview" has no Configure area to jump to, so leave it out of
        // results rather than surface a dead end.
        var help: [HelpSearchResult] = ConfigGuide.sectionIDs.compactMap { id in
            guard id != "Overview", let body = helpGuide[id],
                  let snippet = Self.searchSnippet(in: body, matching: query) else { return nil }
            return HelpSearchResult(id: id, sectionID: id, snippet: snippet)
        }
        if let teamGuide = TeamRecipeStore.shared.guide,
           let snippet = Self.searchSnippet(in: teamGuide, matching: query) {
            help.append(HelpSearchResult(id: "team-guide", sectionID: "My Team", snippet: snippet))
        }
        return (changes, help)
    }

    /// First matching excerpt of `query` in `text` (case-insensitive), trimmed
    /// to roughly 100 characters of surrounding context. Nil when there's no match.
    private static func searchSnippet(in text: String, matching query: String) -> String? {
        guard let range = text.range(of: query, options: .caseInsensitive) else { return nil }
        let start = text.index(range.lowerBound, offsetBy: -50, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(range.upperBound, offsetBy: 50, limitedBy: text.endIndex) ?? text.endIndex
        var s = text[start..<end].replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        if start != text.startIndex { s = "…" + s }
        if end != text.endIndex { s += "…" }
        return s
    }

    // MARK: help guide

    /// Load (or refresh) the agent-generated guide to the current config.
    /// Cache hit shows instantly; otherwise runs the selected agent off the main actor.
    func loadHelpGuide(force: Bool = false) {
        guard !helpGuideLoading else { return }
        helpGuideLoading = true
        helpGuideError = nil
        let repo = paths.repoDir
        let hb = paths.homebrewData
        Task.detached {
            let result = await ConfigGuide.generate(cwd: repo, homebrewData: hb, force: force)
            await MainActor.run {
                switch result {
                case .success(let text):
                    self.helpGuide = RecipeGuideStore.combining(
                        ConfigGuide.sections(from: text), in: repo)
                case .failure(let error):
                    self.helpGuideError = error.localizedDescription
                }
                self.helpGuideLoading = false
            }
        }
    }

    /// Run as its own visible pipeline step, between Format and Commit. Only
    /// bothers if the guide has been generated at least once (no point paying
    /// for agent calls a user has never looked at) *and* this apply's diff
    /// actually touches something the guide describes — most applies don't,
    /// so this is usually a free, instant skip with no step shown at all.
    /// When it does run, it hands the selected agent just the diff (not the whole config)
    /// and asks it to touch only the affected section(s), so it's both fast
    /// (small input) and surgical (rest of the guide passes through
    /// untouched). If the result differs from what's on disk, writes
    /// `GUIDE.md` at the repo root — staged alongside the config change so it
    /// lands in the same commit and the guide's history never lags behind the
    /// config it describes.
    private func updateGuideStep(diff: String) async {
        guard settings.keepGuideUpdated, !helpGuide.isEmpty,
              diff != "No uncommitted changes." else { return }
        guard diff.contains("flake.nix") || diff.contains("home.nix")
            || diff.contains("modules/darwin/") || diff.contains("modules/home/")
            || diff.contains(".nixmc/homebrew/data.json") else { return }

        let step = beginStep("Update guide")
        helpGuideLoading = true
        let repo = paths.repoDir
        let before = helpGuide
        let generatedBefore = RecipeGuideStore.removingBlocks(from: before)
        guard let text = await ConfigGuide.update(existing: generatedBefore, diff: diff, cwd: repo) else {
            stepOut(step, "Couldn't refresh the guide.")
            finishStep(step, ok: true)
            helpGuideLoading = false
            return
        }
        let generatedAfter = ConfigGuide.sections(from: text)
        let after = RecipeGuideStore.combining(generatedAfter, in: repo)
        helpGuide = after
        helpGuideLoading = false

        let guideURL = repo.appending(path: "GUIDE.md")
        let previous = try? String(contentsOf: guideURL, encoding: .utf8)
        let combinedText = ConfigGuide.markdown(from: after)
        guard previous != combinedText else {
            stepOut(step, "Guide unchanged.")
            finishStep(step, ok: true)
            return
        }
        try? combinedText.write(to: guideURL, atomically: true, encoding: .utf8)
        let touched = ConfigGuide.sectionIDs.filter { generatedAfter[$0] != generatedBefore[$0] }
        stepOut(step, touched.isEmpty ? "Updated GUIDE.md." : "Updated: \(touched.joined(separator: ", ")).")
        finishStep(step, ok: true)
    }

    func apply() {
        run {
            // Build first if we haven't already verified this state — Apply must
            // work for any pending changes, not only ones just built this session.
            self.stopped = false
            let repo = self.paths.repoDir
            if !self.buildOK {
                self.activity = "Building…"
                let buildStep = self.beginStep("Build configuration")
                let built = await self.runBuild { self.stepOut(buildStep, $0) }
                self.finishStep(buildStep, ok: built && !self.stopped)
                if self.stopped {
                    self.transcript.append(ChatMessage(role: .system, text: "Build stopped."))
                    return
                }
                self.buildOK = built
                self.buildFailed = !built
                guard built else {
                    self.transcript.append(ChatMessage(role: .system,
                        text: "Build failed. Use “Fix with agent” to hand it the error."))
                    return
                }
            }
            self.activity = "Applying…"
            let applyStep = self.beginStep("Apply (darwin-rebuild switch)")
            var applyOutput: [String] = []
            let ok = await DarwinRebuild.switchTo(host: self.host) { line in
                Task { @MainActor in applyOutput.append(line); self.stepOut(applyStep, line) }
            }
            self.finishStep(applyStep, ok: ok)
            guard ok else {
                self.transcript.append(ChatMessage(role: .system, text: "Apply failed — see the step log above."))
                return
            }
            // darwin-rebuild/Homebrew often surface things worth reflecting in
            // the config (a cask renamed/adopted, a deprecation notice) — give
            // the agent a chance to catch up on those before we commit.
            if self.settings.reviewApplyOutput { await self.reviewApplyOutput(applyOutput) }
            if self.settings.autoFormat { await self.formatStep() }
            // git shell-outs are synchronous and can be slow (a large diff,
            // per-untracked-file `--no-index`); run them off the main actor so
            // the UI keeps painting instead of freezing.
            let diff = await Task.detached { Git.workingDiff(in: repo) }.value
            // Surgically refresh GUIDE.md (if it's ever been viewed and this
            // diff actually touches something it describes) before the
            // commit, so any update rides along in the same commit.
            await self.updateGuideStep(diff: diff)
            self.copyPendingRecipeGuide()
            // Every successful apply becomes a commit (that's the history /
            // rollback model) — surface failures instead of dropping them.
            self.activity = "Committing…"
            let commitStep = self.beginStep("Commit")
            let drafted = (diff == "No uncommitted changes." || !self.settings.aiCommitMessages) ? nil
                : await Summarizer.commitMessage(for: diff, cwd: repo)
            // A failed/unavailable agent must not turn the full conversational
            // request into a Git subject. Keep the fallback short and tied to
            // the thing this app manages.
            let message = drafted ?? "Update nix-darwin configuration"
            self.stepOut(commitStep, "› git commit -m \(message)")
            let commitError: String? = await Task.detached {
                do { try Git.commitAll(message, in: repo); return nil }
                catch { return error.localizedDescription }
            }.value
            let committed = commitError == nil
            if let commitError { self.stepOut(commitStep, "Commit failed: \(commitError)") }
            else { self.stepOut(commitStep, "Committed.") }
            self.finishStep(commitStep, ok: committed)
            if committed, self.settings.autoPush { await self.pushToRemote() }
            self.reloadCommits()
            self.loadHomebrew()
            self.pending = await Task.detached { Git.hasChanges(in: repo) }.value
            self.buildOK = false
            let msg = committed && !self.pending
                ? "Applied and committed."
                : "Applied, but committing failed — changes are still pending (see log)."
            if committed && !self.pending { self.removeSuccessfulPipelineSteps() }
            self.transcript.append(ChatMessage(role: .system, text: msg))
        }
    }

    /// The recipe preview is the explicit approval point. Once added, send it
    /// through the normal conversation path immediately.
    func present(recipe: Recipe) {
        showTemplates = false
        send(recipe.agentRequest, display: recipe.title, recipe: recipe)
    }

    /// Removes the recipe card from the visible conversation. It does not
    /// rewrite an already-running agent request or its response.
    func removeRecipe(messageID: UUID) {
        transcript.removeAll { $0.id == messageID && $0.recipe != nil }
    }

    private func copyPendingRecipeGuide() {
        guard let recipe = pendingRecipeGuide, recipe.guide != nil else { return }
        defer { pendingRecipeGuide = nil }
        let guideURL = paths.repoDir.appending(path: "GUIDE.md")
        do {
            try RecipeGuideStore.store(recipe, in: paths.repoDir)
            var sections = helpGuide
            if sections.isEmpty, let text = try? String(contentsOf: guideURL, encoding: .utf8) {
                sections = ConfigGuide.sections(from: text)
            }
            sections = RecipeGuideStore.combining(
                RecipeGuideStore.removingBlocks(from: sections), in: paths.repoDir)
            let text = ConfigGuide.markdown(from: sections)
            try text.write(to: guideURL, atomically: true, encoding: .utf8)
            helpGuide = sections
            out("Stored \(recipe.title) guide notes and assembled GUIDE.md")
        } catch {
            transcript.append(ChatMessage(role: .system,
                text: "Couldn't update GUIDE.md: \(error.localizedDescription)"))
        }
    }

    func showDiff(_ commit: Git.Commit) {
        diffCommit = commit
        diffText = "Loading…"
        resetSummary()
        let repo = paths.repoDir
        Task.detached {
            let text = Git.show(commit.id, in: repo)
            await MainActor.run {
                self.diffText = text
                self.loadSummary(for: text)
            }
        }
    }

    func rollback(_ commit: Git.Commit) {
        run {
            do {
                try Git.revert(commit.id, in: self.paths.repoDir)
                self.out("Reverted \(commit.id). Re-applying…")
                _ = await DarwinRebuild.switchTo(host: self.host) { line in Task { @MainActor in self.out(line) } }
                self.reloadCommits()
                self.loadHomebrew()
                self.pending = Git.hasChanges(in: self.paths.repoDir)
                if self.settings.autoPush { await self.pushToRemote() }
            } catch {
                self.out("Rollback failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: remote sync

    /// Manual push (Settings → Sync → Push Now) — the first sync of an existing
    /// history, or a retry after a failed auto-push. Ignores the auto-push toggle.
    func pushNow() {
        run { await self.pushToRemote() }
    }

    /// Download remote configuration commits without applying them. A pull is
    /// refused when local edits exist, and only fast-forward updates are used,
    /// so the user can resolve any divergence deliberately in Git.
    func pullNow() {
        guard !settings.resolvedGitRemote.isEmpty else {
            out("Configure a remote before pulling.")
            return
        }
        run {
            let repo = self.paths.repoDir
            let hasLocalChanges = await Task.detached { Git.hasChanges(in: repo) }.value
            guard !hasLocalChanges else {
                self.out("Pull skipped: commit, apply, or discard local changes before pulling.")
                return
            }

            self.activity = "Pulling…"
            let step = self.beginStep("Pull from remote")
            self.stepOut(step, "› git pull --ff-only")
            let remote = self.settings.resolvedGitRemote
            let error: String? = await Task.detached {
                do {
                    try Git.setRemote(remote, in: repo)
                    try Git.pull(in: repo)
                    return nil
                } catch { return error.localizedDescription }
            }.value
            if let error {
                self.stepOut(step, error)
            } else {
                self.stepOut(step, "Pulled. Build and apply the downloaded configuration when ready.")
                self.reloadCommits()
                self.loadHomebrew()
            }
            self.finishStep(step, ok: error == nil)
            self.pending = await Task.detached { Git.hasChanges(in: repo) }.value
        }
    }

    /// Push HEAD to the remote configured in Settings, as its own transcript
    /// step. Points `origin` at the setting first, so URL edits apply here.
    /// Best-effort: a failed push shows a failed step but blocks nothing —
    /// the commit is already local, so nothing is lost.
    @discardableResult
    private func pushToRemote() async -> Bool {
        let url = settings.resolvedGitRemote
        guard !url.isEmpty else { return true }
        let repo = paths.repoDir
        activity = "Pushing…"
        let step = beginStep("Push to remote")
        stepOut(step, "› git push \(url)")
        let error: String? = await Task.detached {
            do {
                try Git.setRemote(url, in: repo)
                try Git.push(in: repo)
                return nil
            } catch { return error.localizedDescription }
        }.value
        if let error { stepOut(step, error) } else { stepOut(step, "Pushed.") }
        finishStep(step, ok: error == nil)
        return error == nil
    }

    // MARK: updates
    //
    // Weekly flake-update proposals. The pipeline runs in an isolated worktree
    // and never touches the main working tree or the `busy` gate; only
    // `applyProposal` (which mutates the main tree) goes through `run {}`.
    // AppState owns all proposals.json I/O, on the main actor.

    /// Load persisted proposals, then reap orphans and entries whose commits
    /// vanished (e.g. the repo was re-cloned). Guarded — `refresh()` re-runs on
    /// every window appear.
    func loadUpdatesStore() {
        guard !updatesStoreLoaded else { return }
        updatesStoreLoaded = true
        let repo = paths.repoDir
        Task.detached {
            var store = UpdatesStorage.load()
            UpdatePipeline.cleanupOrphans(repo: repo, known: store.proposals)
            let alive = store.proposals.filter { Git.revParse($0.tipCommit, in: repo) != nil }
            if alive.count != store.proposals.count {
                store.proposals = alive
                try? UpdatesStorage.save(store)
            }
            let final = store
            await MainActor.run {
                self.proposals = final.proposals
                self.lastUpdateCheck = final.lastChecked
            }
        }
    }

    func startUpdateSchedulerIfNeeded() {
        guard !schedulerStarted else { return }
        schedulerStarted = true
        updateScheduler.start(
            shouldRun: { [weak self] in
                guard let self else { return false }
                return self.settings.autoUpdateChecks
                    && self.phase == .ready && !self.busy && !self.updateChecking
                    && self.isUpdateDue
                    && UpdateScheduler.secondsSinceLastUserInput() >= self.settings.idleSeconds
            },
            fire: { [weak self] in await self?.runUpdateCheck() })
    }

    // MARK: app self-update

    /// One launch-time check, gated by the setting; failures stay silent
    /// (the next launch or manual check retries).
    private func checkForAppUpdateAtLaunch() {
        guard !selfUpdateCheckedAtLaunch else { return }
        selfUpdateCheckedAtLaunch = true
        guard settings.autoSelfUpdate else { return }
        Task { await checkForAppUpdate() }
    }

    func checkForAppUpdate() async {
        appUpdate = (try? await SelfUpdater.check()) ?? appUpdate
    }

    /// Download, verify, and install `appUpdate`; the app relaunches itself
    /// on success, so this only "returns" on failure.
    func installAppUpdate() {
        guard let release = appUpdate, !appUpdating else { return }
        appUpdating = true
        appUpdateError = nil
        Task {
            do {
                try await SelfUpdater.installAndRelaunch(release)
            } catch {
                appUpdateError = error.localizedDescription
                appUpdating = false
            }
        }
    }

    /// Manual trigger — skips the idle and weekly gates.
    func checkForUpdatesNow() {
        guard phase == .ready, !updateChecking else { return }
        Task { await runUpdateCheck() }
    }

    private func runUpdateCheck() async {
        guard !updateChecking else { return }
        updateChecking = true
        defer { updateChecking = false }
        // Long-running sessions piggyback the app's own update check on the
        // flake cadence; launch-time covers everything shorter.
        if settings.autoSelfUpdate { await checkForAppUpdate() }
        // Stream into the chat transcript (like build/apply) rather than the
        // bootstrap-only `log`, so the running check is visible wherever the
        // user is, not just on the bootstrap screens.
        let step = beginStep("Checking for flake updates")
        let repo = paths.repoDir
        let host = host
        let existing = proposals
        let outcome = await Task.detached {
            await UpdatePipeline.run(repo: repo, host: host, existing: existing) { line in
                Task { @MainActor in self.stepOut(step, line) }
            }
        }.value
        switch outcome {
        case .created(let p):
            proposals.append(p)
            // Prune oldest beyond the cap; drop their worktrees/branches too.
            while proposals.count > settings.maxProposals {
                let evicted = proposals.removeFirst()
                Task.detached { UpdatePipeline.discardArtifacts(of: evicted, repo: repo) }
            }
            lastUpdateCheck = .now
            stepOut(step, "Update proposal ready: \(p.title)")
            finishStep(step, ok: true)
        case .noChanges, .duplicate:
            lastUpdateCheck = .now
            finishStep(step, ok: true)
        case .failed(let why):
            // lastUpdateCheck stays put, so the next 30-min tick retries.
            stepOut(step, "Update check failed: \(why)")
            finishStep(step, ok: false)
        }
        saveUpdatesStore()
    }

    private func saveUpdatesStore() {
        var snapshot = UpdatesStore()
        snapshot.lastChecked = lastUpdateCheck
        snapshot.proposals = proposals
        let store = snapshot
        Task.detached { try? UpdatesStorage.save(store) }
    }

    /// Show a proposal in the detail pane (mirrors `showDiff`).
    func selectProposal(_ p: UpdateProposal) {
        selectedProposalID = p.id
        proposalDiffText = "Loading…"
        proposalActionError = nil
        resetSummary()
        let repo = paths.repoDir
        Task.detached {
            let text = Git.diff(p.baseCommit, p.tipCommit, in: repo)
            await MainActor.run {
                guard self.selectedProposalID == p.id else { return }
                self.proposalDiffText = text
                self.loadSummary(for: text)
            }
        }
    }

    func closeProposal() {
        selectedProposalID = nil
        proposalDiffText = ""
        proposalActionError = nil
    }

    /// `summary`/`summarizing` are shared with the diff sheets — opening a
    /// commit-diff sheet over the proposal pane repoints them. Call from the
    /// sheets' onClose to repoint back (cache hit → instant).
    func restoreProposalSummaryIfNeeded() {
        guard selectedProposal != nil else { return }
        resetSummary()
        loadSummary(for: proposalDiffText)
    }

    /// Stage the proposal's commit into the main working tree (no commit); the
    /// existing pending flow (Review diff → Build & Apply) takes over.
    func applyProposal(_ p: UpdateProposal) {
        run {
            self.proposalActionError = nil
            let repo = self.paths.repoDir
            let pickError: String? = await Task.detached {
                do { try Git.cherryPickNoCommit(p.tipCommit, in: repo); return nil }
                catch { return error.localizedDescription }
            }.value
            if let pickError {
                self.proposalActionError = pickError
                return
            }
            await Task.detached { UpdatePipeline.discardArtifacts(of: p, repo: repo) }.value
            self.proposals.removeAll { $0.id == p.id }
            self.saveUpdatesStore()
            self.closeProposal()
            self.pending = await Task.detached { Git.hasChanges(in: repo) }.value
            self.buildOK = false
            self.buildFailed = false
            self.transcript.append(ChatMessage(role: .system,
                text: "Update staged — review the diff, then Build & Apply."))
        }
    }

    /// Throw the proposal away (worktree, branch, metadata). Doesn't touch the
    /// main tree, so no busy gate.
    func dismissProposal(_ p: UpdateProposal) {
        let repo = paths.repoDir
        Task.detached { UpdatePipeline.discardArtifacts(of: p, repo: repo) }
        proposals.removeAll { $0.id == p.id }
        saveUpdatesStore()
        if selectedProposalID == p.id { closeProposal() }
    }

    // MARK: helpers

    private func run(_ work: @escaping () async -> Void) {
        busy = true
        Task {
            await work()
            self.busy = false
            self.sendNextQueuedMessageIfPossible()
        }
    }
}
