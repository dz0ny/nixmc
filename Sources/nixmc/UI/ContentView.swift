import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var app: AppState
    @ObservedObject private var teamRecipes = TeamRecipeStore.shared
    @State private var draft = ""
    @FocusState private var inputFocused: Bool
    /// Global search over commit history (subject + AI summary) and the
    /// config guide. Non-empty text swaps the sidebar's normal sections for
    /// inline results, sectioned like a command bar.
    @State private var searchQuery = ""
    /// Homebrew browser is shown in the main content area (in place of the chat)
    /// when the user opens it from the sidebar.
    @State private var showPackages = false
    /// The selected Configure area, shown as a grid of context-aware recipes in
    /// the main content area. `nil` means the chat is showing.
    @State private var selectedArea: StarterArea?
    /// Recipes and the generated guide share a Configure area but occupy
    /// separate tabs. Help search results can jump directly to the guide.
    @State private var selectedAreaTab: SectionPaneTab = .recipes
    @State private var showClearConversationConfirmation = false
    @State private var recipePreview: Recipe?
    @State private var remoteConfigURL = ""
    @State private var historyExpanded = true
    @State private var collapsedHistoryDays: Set<Date> = []
    /// Older history starts folded; this stores only the date groups the user
    /// explicitly opened during the current app session.
    @State private var expandedOlderHistoryDays: Set<Date> = []

    /// Focused, recognizable areas of the nix config — the handful of things
    /// people actually change. Selecting one opens a grid of context-aware
    /// recipes (see `StarterPrompts.areas`, the single source of truth). The
    /// agent finds and edits the right file.
    private var configAreas: [StarterArea] { StarterPrompts.areas }

    private struct HistoryGroup: Identifiable {
        let day: Date
        let commits: [Git.Commit]
        var id: Date { day }
    }

    private var historyGroups: [HistoryGroup] {
        Dictionary(grouping: app.commits) { Calendar.current.startOfDay(for: $0.date) }
            .map { HistoryGroup(day: $0.key, commits: $0.value) }
            .sorted { $0.day > $1.day }
    }

    private var statusColor: Color {
        switch app.statusKind {
        case .idle: return .green
        case .working: return Theme.accent
        case .attention: return .orange
        case .error: return Color(red: 0.85, green: 0.3, blue: 0.3)
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            Group {
                switch app.phase {
                case .checking: ProgressView("Checking…")
                case .needsNix: nixSetup
                case .needsConfig: configurationSetup
                case .ready:
                    if !trimmedSearch.isEmpty {
                        searchResultsPane
                    } else if let p = app.selectedProposal {
                        UpdateProposalView(proposal: p)
                    } else if showPackages {
                        PackagesView(casks: app.casks, brews: app.brews,
                                     onInsert: { prompt in seed(prompt) },
                                     composer: inputBar)
                    } else if let area = selectedArea {
                        SectionRecipesView(area: area,
                                            guide: app.helpGuide[area.id],
                                            guideLoading: app.helpGuideLoading,
                                            guideError: app.helpGuideError,
                                            helpTextScale: app.helpTextScale,
                                            selectedTab: $selectedAreaTab,
                                            busy: app.busy,
                                            onPick: { recipe in recipePreview = recipe },
                                            onAppear: { app.loadHelpGuide() },
                                            onRegenerate: { app.loadHelpGuide(force: true) },
                                            onDecreaseText: app.decreaseHelpTextSize,
                                            onResetText: app.resetHelpTextSize,
                                            onIncreaseText: app.increaseHelpTextSize,
                                            onSourceSaved: app.refresh,
                                            composer: inputBar)
                    } else {
                        chat
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .tint(Theme.accent)
        .frame(minWidth: 900, minHeight: 620)
        // Docked in the window's title bar (top of the window, like Mail/Notes)
        // rather than a custom field embedded in the sidebar — typing swaps the
        // sidebar's normal sections for inline, sectioned results.
        .searchable(text: $searchQuery, placement: .toolbar, prompt: "Search changes & help")
        .onChange(of: searchQuery) { _, q in
            if !q.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { app.ensureSearchIndexed() }
        }
        .onAppear { app.refresh() }
        .onChange(of: app.updateChecking) { _, checking in
            // A check streams its output into the chat transcript (see
            // `runUpdateCheck`); don't let it run invisibly behind whatever
            // pane the user happens to be on.
            if checking {
                showPackages = false
                selectedArea = nil
                app.closeProposal()
            }
        }
        .sheet(isPresented: $app.showTemplates) {
            TemplatesView { recipe in
                app.showTemplates = false
                app.present(recipe: recipe)
            } onClose: { app.showTemplates = false }
        }
        .sheet(item: $recipePreview) { recipe in
            RecipePreviewSheet(recipe: recipe) {
                selectedArea = nil
                showPackages = false
                app.closeProposal()
                app.present(recipe: recipe)
            } onEditPrompt: {
                selectedArea = nil
                showPackages = false
                app.closeProposal()
                seed(recipe.agentRequest)
            }
        }
        .sheet(isPresented: $app.showWorkingDiff) {
            DiffView(title: "Uncommitted changes", diff: app.workingDiffText,
                     summary: app.summary, summarizing: app.summarizing,
                     onRegenerate: { app.regenerateSummary() }) {
                app.showWorkingDiff = false
                app.restoreProposalSummaryIfNeeded()
            }
        }
        .sheet(item: $app.diffCommit) { commit in
            DiffView(title: "\(commit.id) · \(commit.subject)", diff: app.diffText,
                     summary: app.summary, summarizing: app.summarizing,
                     onRegenerate: { app.regenerateSummary() }) {
                app.diffCommit = nil
                app.restoreProposalSummaryIfNeeded()
            }
        }
        .alert("Clear conversation?", isPresented: $showClearConversationConfirmation) {
            Button("Clear", role: .destructive) {
                app.clearConversation()
                inputFocused = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the visible messages. Pending configuration changes are kept.")
        }
    }

    // MARK: sidebar

    private var sidebar: some View {
        List {
            Section {
                HStack(spacing: 10) {
                    BrandMark(size: 30)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("NixMC").font(.headline)
                        Text(app.host).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                .listRowSeparator(.hidden)
            }

            normalSections
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(.thinMaterial)
        .frame(minWidth: 250)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SettingsLink {
                Label("Settings", systemImage: "gearshape")
                    .font(.callout)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial)
            .help("Open NixMC settings (⌘,)")
        }
    }

    private var trimmedSearch: String { searchQuery.trimmingCharacters(in: .whitespacesAndNewlines) }

    // MARK: search results (main content)

    /// Inline search results, shown in the main content area (in place of the
    /// chat) while the title-bar search field has text — sectioned like a
    /// command bar: matching recipes, commits, and config-guide sections.
    private var searchResultsPane: some View {
        let results = app.search(trimmedSearch)
        let recipes = RecipeCatalog.search(trimmedSearch)
        return ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Search results")
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                    Text("Matching “\(trimmedSearch)”").font(.callout).foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Recipes").font(.headline)
                    if recipes.isEmpty {
                        Text("No matching recipes").foregroundStyle(.secondary).font(.callout)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(recipes) { recipe in searchRecipeRow(recipe) }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Changes").font(.headline)
                    if results.changes.isEmpty {
                        Text("No matching changes").foregroundStyle(.secondary).font(.callout)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(results.changes) { r in searchChangeRow(r) }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Help").font(.headline)
                    if results.help.isEmpty {
                        Text("No matching help topics").foregroundStyle(.secondary).font(.callout)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(results.help) { r in searchHelpRow(r) }
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 1040, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func searchRecipeRow(_ recipe: Recipe) -> some View {
        Button {
            recipePreview = recipe
            searchQuery = ""
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: recipe.symbol)
                    .font(.caption).foregroundStyle(Theme.accent).padding(.top, 2)
                VStack(alignment: .leading, spacing: 3) {
                    Text(recipe.title).font(.callout.weight(.semibold)).lineLimit(1)
                    Text("\(recipe.section) · \(recipe.summary)")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .help("Use \(recipe.title) recipe")
    }

    private func searchChangeRow(_ r: AppState.ChangeSearchResult) -> some View {
        Button {
            app.showDiff(r.commit)
            searchQuery = ""
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.caption).foregroundStyle(Theme.accent).padding(.top, 2)
                VStack(alignment: .leading, spacing: 3) {
                    Text(r.commit.subject).font(.callout.weight(.semibold)).lineLimit(1)
                    Text(r.snippet).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .help("Show diff for \(r.commit.id)")
    }

    private func searchHelpRow(_ r: AppState.HelpSearchResult) -> some View {
        Button {
            if let area = configAreas.first(where: { $0.id == r.sectionID }) {
                showPackages = false
                app.closeProposal()
                selectedArea = area
                selectedAreaTab = .guide
            }
            searchQuery = ""
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "questionmark.circle").font(.caption).foregroundStyle(Theme.accent).padding(.top, 2)
                VStack(alignment: .leading, spacing: 3) {
                    Text(r.sectionID).font(.callout.weight(.semibold))
                    Text(r.snippet).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .help("Open \(r.sectionID.lowercased()) guide")
    }

    /// The sidebar's normal sections, shown whenever search is empty.
    @ViewBuilder private var normalSections: some View {
        Group {
            Section("Status") {
                // Always return to the chat workspace. Pending changes expose
                // Build & Apply there, while History remains the dedicated
                // route for opening the uncommitted diff.
                Button { goHome() } label: {
                    HStack(spacing: 8) {
                        Circle().fill(statusColor)
                            .frame(width: 8, height: 8)
                            .shadow(color: statusColor.opacity(0.6), radius: 3)
                        Text(app.statusText).font(.callout)
                        Spacer()
                        if app.statusKind == .working {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "chevron.right")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(app.pending ? "Open Build & Apply" : "Back to chat")
            }

            // The things people actually change, as focused areas — so it's clear
            // what you can do. Selecting one opens a grid of context-aware
            // starters for that area (e.g. common Services or macOS Settings),
            // plus an agent-generated guide to what's actually configured
            // there — the two share one entry point instead of a parallel
            // "Help" taxonomy.
            Section("Configure") {
                ForEach(configAreas) { area in
                    let isSelected = selectedArea?.id == area.id && !showPackages
                    Button { selectArea(area) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: area.symbol).font(.caption2)
                                .foregroundStyle(Theme.accent).frame(width: 16)
                            Text(area.id).font(.callout)
                            Spacer(minLength: 0)
                            if isSelected {
                                Image(systemName: "chevron.right")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .listRowBackground(isSelected ? Theme.accent.opacity(0.10) : Color.clear)
                    .help("Browse \(area.id.lowercased()) recipes")
                }
            }

            // Homebrew apps + CLI tools open in a browser pane in the main
            // content area, where ticking entries builds a change request.
            if !app.casks.isEmpty || !app.brews.isEmpty {
                Section("Homebrew") {
                    Button {
                        if showPackages { showPackages = false } else {
                            showPackages = true; selectedArea = nil; app.closeProposal()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "mug").font(.caption2)
                                .foregroundStyle(Theme.accent).frame(width: 16)
                            Text("Browse packages").font(.callout)
                            Spacer(minLength: 0)
                            Text("\(app.casks.count + app.brews.count)")
                                .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                            Image(systemName: "chevron.right")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .fontWeight(showPackages ? .semibold : .regular)
                    .listRowBackground(showPackages ? Theme.accent.opacity(0.10) : Color.clear)
                    .help("Browse installed apps & CLI tools and build a change request")
                }
            }

            // Weekly flake-update proposals, produced in the background while
            // the machine is idle. Selecting one shows its diff + summary in
            // the main content area with Apply / Dismiss.
            if app.phase == .ready {
                Section("Updates") {
                    ForEach(app.proposals.reversed()) { p in proposalRow(p) }
                    checkRow
                }
            }

            Section {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        historyExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text("History")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(historyExpanded ? 0 : -90))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(historyExpanded ? "Collapse history" : "Expand history")

                if historyExpanded {
                    // Uncommitted edits sit at the head of the timeline — one entry
                    // standing in for everything done since the last commit, opening
                    // the working diff. It's the "pending commit" the chat is building.
                    if app.pending {
                        Button { app.reviewChanges() } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "pencil.circle.fill")
                                    .font(.caption2).foregroundStyle(.orange)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Uncommitted changes").font(.callout)
                                    Text("since last commit")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Review the uncommitted changes since the last commit")
                    }
                    if app.commits.isEmpty && !app.pending {
                        Text("No changes applied yet").foregroundStyle(.secondary).font(.callout)
                    }
                    ForEach(historyGroups) { group in
                        let collapsed = isHistoryGroupCollapsed(group.day)
                        Button {
                            toggleHistoryGroup(group.day)
                        } label: {
                            HStack(spacing: 6) {
                                Text(historyLabel(for: group.day))
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 8, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                                    .rotationEffect(.degrees(collapsed ? -90 : 0))
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(collapsed ? "Expand \(historyLabel(for: group.day))" : "Collapse \(historyLabel(for: group.day))")
                            .padding(.top, 5)
                            .listRowSeparator(.hidden)
                        if !collapsed {
                            ForEach(group.commits) { c in commitRow(c) }
                        }
                    }
                }
            }
        }
    }

    /// Prefill the chat input and focus it, without sending. The composer is
    /// visible in every pane, so this no longer needs to navigate back to chat.
    private func seed(_ text: String) {
        draft = text
        inputFocused = true
    }

    /// Toggle a Configure area's starter grid. Re-selecting the open area returns
    /// to the chat, so the sidebar row acts as a toggle.
    private func selectArea(_ area: StarterArea) {
        showPackages = false
        app.closeProposal()
        if area.id == "My Team" {
            teamRecipes.fetchIfNeeded(maxAge: 60)
        }
        if selectedArea?.id == area.id {
            selectedArea = nil
        } else {
            selectedArea = area
            selectedAreaTab = .recipes
        }
    }

    /// Back to the main chat / starters view from any focused pane.
    private func goHome() {
        showPackages = false
        selectedArea = nil
        app.closeProposal()
    }

    private func proposalRow(_ p: UpdateProposal) -> some View {
        let isSelected = app.selectedProposalID == p.id
        return Button {
            showPackages = false
            selectedArea = nil
            app.selectProposal(p)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: proposalIcon(p))
                    .font(.caption2).foregroundStyle(proposalTint(p))
                VStack(alignment: .leading, spacing: 1) {
                    Text(p.title).font(.callout).lineLimit(1)
                    Text(p.createdAt.formatted(.relative(presentation: .named)))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "chevron.right")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fontWeight(isSelected ? .semibold : .regular)
        .listRowBackground(isSelected ? Theme.accent.opacity(0.10) : Color.clear)
        .help("Review this proposed update")
    }

    private func proposalIcon(_ p: UpdateProposal) -> String {
        switch p.buildStatus {
        case .ok: return "checkmark.seal.fill"
        case .failed: return "xmark.seal.fill"
        case .unverified: return "clock"
        }
    }

    private func proposalTint(_ p: UpdateProposal) -> Color {
        switch p.buildStatus {
        case .ok: return .green
        case .failed: return Color(red: 0.85, green: 0.3, blue: 0.3)
        case .unverified: return .secondary
        }
    }

    private var checkRow: some View {
        Group {
            if app.updateChecking {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Checking for updates…").font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button { app.checkForUpdatesNow() } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption2).foregroundStyle(Theme.accent).frame(width: 16)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Check now").font(.callout)
                            Text(app.lastUpdateCheck.map {
                                "Checked \($0.formatted(.relative(presentation: .named)))"
                            } ?? "Never checked")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Run a flake-update check now")
            }
        }
    }

    private func commitRow(_ c: Git.Commit) -> some View {
        HStack(spacing: 8) {
            Button { app.showDiff(c) } label: {
                HStack(spacing: 8) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .font(.caption2).foregroundStyle(Theme.accent)
                    Text(c.subject).lineLimit(1).font(.callout)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Show diff for \(c.id)")
            Button { app.rollback(c) } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .buttonStyle(.borderless).font(.caption).foregroundStyle(.secondary)
            .help("Roll back this change")
        }
        .padding(.vertical, 2)
    }

    private func historyLabel(for day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        if calendar.component(.year, from: day) == calendar.component(.year, from: .now) {
            return day.formatted(.dateTime.month(.abbreviated).day())
        }
        return day.formatted(.dateTime.month(.abbreviated).day().year())
    }

    private func toggleHistoryGroup(_ day: Date) {
        withAnimation(.easeInOut(duration: 0.15)) {
            if Calendar.current.isDateInToday(day) {
                if collapsedHistoryDays.contains(day) {
                    collapsedHistoryDays.remove(day)
                } else {
                    collapsedHistoryDays.insert(day)
                }
            } else if expandedOlderHistoryDays.contains(day) {
                expandedOlderHistoryDays.remove(day)
            } else {
                expandedOlderHistoryDays.insert(day)
            }
        }
    }

    private func isHistoryGroupCollapsed(_ day: Date) -> Bool {
        if Calendar.current.isDateInToday(day) {
            return collapsedHistoryDays.contains(day)
        }
        return !expandedOlderHistoryDays.contains(day)
    }

    // MARK: chat

    private var chat: some View {
        VStack(spacing: 0) {
            if !app.transcript.isEmpty {
                conversationHeader
                Divider().opacity(0.5)
            }
            transcriptView
            if !app.queuedMessages.isEmpty {
                queuedMessages
            }
            if app.pending && !app.busy {
                Divider().opacity(0.5)
                pendingBar
            }
            Divider().opacity(0.5)
            inputBar
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: app.busy) { _, busy in
            if !busy { DispatchQueue.main.async { inputFocused = true } }
        }
        .onExitCommand {
            if app.canStop { app.stop() }
        }
        .task { inputFocused = true }
    }

    private var conversationHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "bubble.left.and.bubble.right")
                .foregroundStyle(Theme.accent)
            Text("Conversation").font(.headline)
            Spacer()
            Button {
                showClearConversationConfirmation = true
            } label: {
                Image(systemName: "trash")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(app.busy)
            .help(app.busy ? "Wait for the current task to finish" : "Clear conversation")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    @ViewBuilder private var transcriptView: some View {
        if app.transcript.isEmpty {
            emptyState
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(app.transcript) { m in messageRow(m).id(m.id) }
                    }
                    .padding(20)
                }
                .onChange(of: app.transcript.count) { _, _ in
                    if let last = app.transcript.last {
                        withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                hero
                HStack(alignment: .firstTextBaseline) {
                    Text("Popular recipes")
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                    Spacer()
                    Button { app.showTemplates = true } label: {
                        Label("Browse all", systemImage: "square.grid.2x2")
                    }
                    .buttonStyle(.link)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 12)], spacing: 12) {
                    ForEach(RecipeCatalog.featured) { recipe in
                        FeaturedRecipeCard(recipe: recipe) { recipePreview = recipe }
                            .disabled(app.busy)
                    }
                }
            }
            .padding(32)
            .frame(maxWidth: 1040, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What should your Mac do?")
                .font(.system(size: 24, weight: .semibold))
            Text("Describe the configuration change you want to make.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var pendingBar: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(barTint.opacity(0.15)).frame(width: 34, height: 34)
                Image(systemName: app.buildFailed ? "exclamationmark.triangle.fill" : "pencil.and.list.clipboard")
                    .foregroundStyle(barTint)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(app.buildFailed ? "Build failed" : "Uncommitted changes ready")
                    .font(.subheadline.weight(.semibold))
                Text(pendingSubtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { app.reviewChanges() } label: {
                Label("Review diff", systemImage: "doc.text.magnifyingglass")
            }
            .controlSize(.large)
            if app.buildFailed {
                Button { app.fixBuild() } label: {
                    Label("Fix with agent", systemImage: "wrench.and.screwdriver.fill")
                }
                .buttonStyle(.brand)
                .keyboardShortcut(.defaultAction)
                .disabled(app.busy)
            } else {
                Button { app.apply() } label: {
                    Label(app.buildOK ? "Apply" : "Build & Apply", systemImage: "checkmark.seal.fill")
                }
                .buttonStyle(.brand)
                .keyboardShortcut(.defaultAction)
                .disabled(app.busy)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(barTint.opacity(0.07))
    }

    private var barTint: Color { app.buildFailed ? .red : .orange }

    private var pendingSubtitle: String {
        if app.buildFailed { return "Hand the error to the agent, or review and edit yourself." }
        return app.buildOK ? "Build passed — review, then apply." : "Review the agent's edits, then apply."
    }

    private var inputBar: ComposerBar {
        ComposerBar(draft: $draft, focused: $inputFocused, busy: app.busy, canStop: app.canStop,
                    queueCount: app.queuedMessages.count, onSubmit: submit,
                    onQueue: queueDraft, onStop: { app.stop() })
    }

    private func submit() {
        let p = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty else { return }
        draft = ""
        showPackages = false
        selectedArea = nil
        if app.busy {
            app.enqueue(p)
        } else {
            app.send(p)
        }
    }

    private func queueDraft() {
        let p = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty else { return }
        draft = ""
        app.enqueue(p)
    }

    private var queuedMessages: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Queued messages (\(app.queuedMessages.count))", systemImage: "text.line.first.and.arrowtriangle.forward")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if !app.busy {
                    Button("Send next") { app.resumeQueuedMessages() }
                        .controlSize(.small)
                }
            }
            ForEach(app.queuedMessages) { message in
                HStack(spacing: 8) {
                    Image(systemName: "line.3.horizontal")
                        .foregroundStyle(.secondary)
                    TextField("Queued message", text: Binding(
                        get: { message.text },
                        set: { app.updateQueuedMessage(message.id, text: $0) }), axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...3)
                    Button(role: .destructive) { app.removeQueuedMessage(message.id) } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove queued message")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Theme.brandSoft.opacity(0.38))
    }

    @ViewBuilder
    private func messageRow(_ m: ChatMessage) -> some View {
        if m.role == .step {
            StepRow(step: m)
        } else if let recipe = m.recipe {
            RecipeTranscriptCard(recipe: recipe,
                                 onRemove: { app.removeRecipe(messageID: m.id) })
        } else {
            chatBubble(m)
        }
    }

    private func chatBubble(_ m: ChatMessage) -> some View {
        HStack(alignment: .top, spacing: 12) {
            avatar(for: m.role)
            VStack(alignment: .leading, spacing: 3) {
                Text(label(for: m.role))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(color(for: m.role))
                    .textCase(.uppercase)
                    .tracking(0.6)
                if m.role == .agent {
                    if m.text.isEmpty {
                        Text("…").foregroundStyle(.secondary)
                    } else {
                        AgentTranscript(text: m.text)
                    }
                } else {
                    Text(m.text)
                        .textSelection(.enabled)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(background(for: m.role), in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .strokeBorder(color(for: m.role).opacity(0.12)))
    }

    private struct RecipeTranscriptCard: View {
        let recipe: Recipe
        let onRemove: () -> Void
        @State private var showImplementation = false

        var body: some View {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Theme.brandSoft)
                            .frame(width: 38, height: 38)
                        Image(systemName: recipe.symbol)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("RECIPE · \(recipe.section.uppercased())")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Theme.accent)
                            .tracking(0.5)
                        Text(recipe.title).font(.headline)
                        Text(recipe.summary)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }

                HStack(spacing: 10) {
                    Button(showImplementation ? "Hide implementation" : "Show implementation") {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            showImplementation.toggle()
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    if let source = recipe.source, let url = URL(string: source) {
                        Link(destination: url) {
                            Label("Source", systemImage: "arrow.up.right.square")
                        }
                        .font(.callout)
                        .controlSize(.small)
                    }
                    Spacer()
                    Label("Added to chat", systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button(role: .destructive, action: onRemove) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .help("Remove recipe from conversation")
                }

                if showImplementation {
                    Markdown(text: recipe.body)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08)))
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.brandSoft.opacity(0.42), in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .strokeBorder(Theme.accent.opacity(0.18)))
        }

    }

    private func avatar(for r: ChatMessage.Role) -> some View {
        ZStack {
            Circle().fill(color(for: r).opacity(0.15)).frame(width: 28, height: 28)
            Image(systemName: icon(for: r)).font(.caption).foregroundStyle(color(for: r))
        }
    }

    // MARK: bootstrap

    private var nixSetup: some View {
        VStack(spacing: 18) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Theme.brand)
                .frame(width: 72, height: 72)
                .overlay(Image(systemName: "shippingbox.fill").font(.system(size: 32, weight: .semibold)).foregroundStyle(.white))
                .shadow(color: Theme.accent.opacity(0.24), radius: 8, y: 3)
            Text("Install Nix")
                .font(.system(.title, design: .rounded).weight(.bold))
            Text("NixMC needs Nix, but it never downloads or runs an installer for you.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
            VStack(alignment: .leading, spacing: 8) {
                Label("Download and run Determinate’s graphical Nix installer.", systemImage: "1.circle.fill")
                Label("Return here and check again when installation finishes.", systemImage: "2.circle.fill")
            }
            .font(.callout)
            .frame(maxWidth: 480, alignment: .leading)
            Link(destination: URL(string: "https://determinate.systems/nix-installer")!) {
                Label("Install Nix in about 5 minutes", systemImage: "arrow.up.right.square")
            }
            .buttonStyle(.brand)
            Button("I've installed Nix — Check Again", action: app.refresh)
                .buttonStyle(.bordered)
        }
        .padding(48)
    }

    private var configurationSetup: some View {
        VStack(spacing: 22) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Theme.brand)
                .frame(width: 72, height: 72)
                .overlay(Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 32, weight: .semibold)).foregroundStyle(.white))
                .shadow(color: Theme.accent.opacity(0.24), radius: 8, y: 3)

            VStack(spacing: 6) {
                Text("Set up your configuration")
                    .font(.system(.title, design: .rounded).weight(.bold))
                Text("Start with NixMC's bootstrap or bring in an existing nix-darwin repository.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 540)
            }

            HStack(alignment: .top, spacing: 28) {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Bootstrap configuration", systemImage: "sparkles")
                        .font(.headline)
                    Text("Create a clean nix-darwin and Home Manager flake with NixMC's standard layout.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Create configuration", action: app.createConfig)
                        .buttonStyle(.brandCompact)
                        .disabled(app.busy)
                }
                .frame(width: 260, alignment: .leading)

                Divider().frame(height: 150)

                VStack(alignment: .leading, spacing: 10) {
                    Label("Use remote dotfiles", systemImage: "arrow.down.to.line")
                        .font(.headline)
                    Text("Clone an existing nix-darwin repository and make it the configuration NixMC manages.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        TextField("github.com/you/dotfiles", text: $remoteConfigURL)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                            .textContentType(.URL)
                        Button("Clone") { app.importConfig(remote: remoteConfigURL) }
                            .buttonStyle(.brandCompact)
                            .disabled(app.busy || remoteConfigURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .frame(width: 320, alignment: .leading)
            }
            .padding(.vertical, 4)

            Text("The remote must contain a flake.nix file. NixMC never overwrites an existing local configuration.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Terminal(lines: app.log, busy: app.busy)
                .frame(width: 620, height: 160)
                .clipShape(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08)))
        }
        .padding(48)
    }

    // MARK: styling helpers

    private func icon(for r: ChatMessage.Role) -> String {
        switch r {
        case .user: return "person.fill"
        case .agent: return "sparkles"
        case .system: return "gearshape.fill"
        case .step: return "terminal"
        }
    }
    private func label(for r: ChatMessage.Role) -> String {
        switch r {
        case .user: return "You"; case .agent: return "Agent"
        case .system: return "nixmc"; case .step: return "Step"
        }
    }
    private func color(for r: ChatMessage.Role) -> Color {
        switch r {
        case .user: return Theme.accent; case .agent: return .purple
        case .system: return .secondary; case .step: return .secondary
        }
    }
    private func background(for r: ChatMessage.Role) -> Color {
        switch r {
        case .user: return Theme.accent.opacity(0.06)
        case .agent: return Color.purple.opacity(0.05)
        case .system: return Color.secondary.opacity(0.05)
        case .step: return Color.secondary.opacity(0.05)
        }
    }
}

/// The chat's text input row — extracted so focused panes (Packages, Configure
/// area starters) can embed the same live composer instead of hiding it behind
/// a "Done" button and forcing a trip back to the chat to type anything.
struct ComposerBar: View {
    @Binding var draft: String
    var focused: FocusState<Bool>.Binding
    var busy: Bool
    var canStop: Bool
    var queueCount: Int
    let onSubmit: () -> Void
    let onQueue: () -> Void
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").foregroundStyle(.secondary)
                TextField("Describe a change… e.g. “install Brave and Slack”", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .focused(focused)
                    .onSubmit(onSubmit)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                    .strokeBorder(focused.wrappedValue ? Theme.accent.opacity(0.65) : Color.primary.opacity(0.10),
                                  lineWidth: focused.wrappedValue ? 1.5 : 1))
            .contentShape(Rectangle())
            .onTapGesture { focused.wrappedValue = true }
            .animation(.easeOut(duration: 0.12), value: focused.wrappedValue)

            Button(action: onQueue) {
                Image(systemName: "text.badge.plus")
                    .frame(width: 16)
            }
            .buttonStyle(.bordered)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help(queueCount > 0 ? "Add to queue (\(queueCount) waiting)" : "Add to queue")

            if busy && canStop {
                Button(action: onStop) {
                    Image(systemName: "stop.fill").frame(width: 16)
                }
                .buttonStyle(.brandDanger)
                .help("Stop the running task")
            } else if busy {
                Button {} label: {
                    ProgressView().controlSize(.small).tint(.white).frame(width: 16)
                }
                .buttonStyle(.brand)
                .disabled(true)
                .help("Working…")
            } else {
                Button(action: onSubmit) {
                    Image(systemName: "arrow.up")
                }
                .buttonStyle(.brand)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Section starters pane

enum SectionPaneTab: String, CaseIterable, Identifiable {
    case recipes = "Recipes"
    case guide = "Guide"
    case source = "Source"

    var id: String { rawValue }
}

/// Context-aware recipes for one Configure area (Services, Fonts, …), shown in
/// the main content area when that sidebar row is selected. Selecting a card
/// opens its preview before it can be added to the conversation.
struct SectionRecipesView: View {
    let area: StarterArea
    @ObservedObject private var teamRecipes = TeamRecipeStore.shared
    @ObservedObject private var settings = AppSettings.shared
    private var recipes: [Recipe] { RecipeCatalog.inSection(area.id) }
    /// Agent-generated guide to what's actually configured in this area
    /// (`AppState.helpGuide[area.id]`). `nil` until generated.
    var guide: String?
    var guideLoading: Bool = false
    var guideError: String?
    var helpTextScale: CGFloat = 1
    @Binding var selectedTab: SectionPaneTab
    var busy: Bool
    let onPick: (Recipe) -> Void
    /// Triggers the (lazy, cached) guide generation the first time an area
    /// with no guide yet is shown.
    var onAppear: () -> Void = {}
    var onRegenerate: () -> Void = {}
    var onDecreaseText: () -> Void = {}
    var onResetText: () -> Void = {}
    var onIncreaseText: () -> Void = {}
    var onSourceSaved: () -> Void = {}
    /// The shared chat composer, so this focused starter grid can still send
    /// a freehand request without leaving the pane.
    let composer: ComposerBar

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            Group {
                switch selectedTab {
                case .recipes: recipesPane
                case .guide: guidePane
                case .source:
                    SourceEditorPane(area: area, onSave: onSourceSaved)
                        .id(area.id)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider().opacity(0.5)
            composer
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { loadGuideIfNeeded() }
        .onChange(of: selectedTab) { _, _ in loadGuideIfNeeded() }
        .onChange(of: guide) { _, _ in loadGuideIfNeeded() }
    }

    private var recipesPane: some View {
        ScrollView {
            if recipes.isEmpty, area.id == "My Team" {
                teamRecipesSetup
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 12)], spacing: 12) {
                    ForEach(recipes) { recipe in
                        SectionRecipeCard(recipe: recipe, onSelect: { onPick(recipe) })
                            .disabled(busy)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var teamRecipesSetup: some View {
        VStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.brandSoft)
                    .frame(width: 52, height: 52)
                Image(systemName: "person.3.fill")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(Theme.accent)
            }

            VStack(spacing: 6) {
                Text("Bring in your team recipes")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                Text("Connect the Git repository your team uses for hand-curated NixMC recipes.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 470)
            }

            HStack(spacing: 10) {
                Image(systemName: "link")
                    .foregroundStyle(.secondary)
                TextField("github.com/acme/nixmc-recipes", text: $settings.teamRecipesRepository)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .textContentType(.URL)
                Button("Connect") { teamRecipes.fetchNow() }
                    .buttonStyle(.brandCompact)
                    .disabled(settings.teamRecipesRepository.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || teamRecipes.state == .syncing)
            }
            .padding(.leading, 12)
            .padding(.trailing, 6)
            .padding(.vertical, 6)
            .frame(maxWidth: 560)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10)))

            Text("Add recipe Markdown anywhere in the repository; name files descriptively and include title, section, and summary front matter.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 560)

            if !resolvedTeamRemote.isEmpty {
                Text(resolvedTeamRemote)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }

            Link(destination: URL(string: "https://github.com/dz0ny/nixmc/blob/main/Sources/nixmc/Resources/recipes/ai-agents/codex.md")!) {
                Label("View an example recipe", systemImage: "arrow.up.right.square")
                    .font(.callout)
            }

            switch teamRecipes.state {
            case .idle: EmptyView()
            case .syncing:
                Label("Fetching team recipes…", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .ready(let message):
                Label(message, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 560)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, minHeight: 330)
    }

    private var resolvedTeamRemote: String {
        Git.normalizeRemote(settings.teamRecipesRepository, ssh: settings.teamRecipesUseSSH)
    }

    private var displayedGuide: String? {
        area.id == "My Team" ? teamRecipes.guide : guide
    }

    /// What's actually configured for this area today, generated from the
    /// current flake and kept separate from the starter actions.
    private var guidePane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12 * helpTextScale) {
                HStack(spacing: 12) {
                    Text(area.id == "My Team" ? "Team guide" : "What's configured today")
                        .font(.system(size: 13 * helpTextScale, weight: .semibold))
                    Spacer()
                    if area.id != "My Team" {
                        ControlGroup {
                            Button(action: onRegenerate) {
                                Image(systemName: "arrow.clockwise")
                            }
                            .help("Regenerate guide")
                            Menu {
                                Button("Smaller Text", systemImage: "textformat.size.smaller", action: onDecreaseText)
                                Button("Reset Text Size", systemImage: "arrow.counterclockwise", action: onResetText)
                                Button("Larger Text", systemImage: "textformat.size.larger", action: onIncreaseText)
                            } label: {
                                Image(systemName: "textformat")
                            }
                            .help("Guide text size")
                        }
                        .controlSize(.small)
                        .fixedSize()
                    }
                }
                if let displayedGuide, !displayedGuide.isEmpty {
                    if area.id == "My Team" {
                        Text("From the team repository's GUIDE.md")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Markdown(text: displayedGuide, fontScale: helpTextScale)
                } else if area.id == "My Team" {
                    Text("This team repository does not include a GUIDE.md yet.")
                        .font(.system(size: 13 * helpTextScale))
                        .foregroundStyle(.secondary)
                } else if guideLoading {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Reading your config…")
                            .font(.system(size: 13 * helpTextScale))
                            .foregroundStyle(.secondary)
                    }
                } else if let guideError {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Guide generation failed", systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 13 * helpTextScale, weight: .semibold))
                            .foregroundStyle(.orange)
                        Text(guideError)
                            .font(.system(size: 13 * helpTextScale))
                            .foregroundStyle(.secondary)
                        Button("Try again", action: onRegenerate)
                            .controlSize(.small)
                    }
                } else {
                    Text("No guide yet.")
                        .font(.system(size: 13 * helpTextScale))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func loadGuideIfNeeded() {
        guard area.id != "My Team" else { return }
        if selectedTab == .guide, guide == nil, guideError == nil { onAppear() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.brandSoft).frame(width: 30, height: 30)
                Image(systemName: area.symbol).font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.accent)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(area.id).font(.headline)
                Text(area.summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if area.id == "My Team" {
                Button(action: teamRecipes.fetchNow) {
                    if teamRecipes.state == .syncing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.plain)
                .controlSize(.small)
                .disabled(settings.teamRecipesRepository.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || teamRecipes.state == .syncing)
                .help("Fetch team recipes")
            }
            sectionTabs
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private var sectionTabs: some View {
        HStack(spacing: 18) {
            tabButton(.recipes, symbol: "square.grid.2x2")
            tabButton(.guide, symbol: "book.closed")
            if area.id != "My Team" {
                tabButton(.source, symbol: "chevron.left.forwardslash.chevron.right")
            }
        }
    }

    private func tabButton(_ tab: SectionPaneTab, symbol: String) -> some View {
        let selected = selectedTab == tab
        return Button {
            selectedTab = tab
        } label: {
            Label(tab.rawValue, systemImage: symbol)
                .font(.callout.weight(selected ? .semibold : .regular))
                .foregroundStyle(selected ? Theme.accent : Color.secondary)
                .padding(.vertical, 8)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(selected ? Theme.accent : .clear)
                        .frame(height: 2)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A deliberately narrow editor for the config module that owns the selected
/// area. It never creates files: a missing module needs to be added to the
/// flake's imports first, which is a job for a recipe or the agent.
private struct SourceEditorPane: View {
    let area: StarterArea
    let onSave: () -> Void

    @State private var text = ""
    @State private var savedText = ""
    @State private var error: String?
    @State private var formatting = false

    private var candidates: [String] {
        switch area.id {
        case "Packages": return ["modules/darwin/packages.nix", "flake.nix"]
        case "Fonts": return ["modules/darwin/fonts.nix", "flake.nix"]
        case "macOS Settings": return ["modules/darwin/macos-settings.nix", "flake.nix"]
        case "Services": return ["modules/darwin/services.nix", "flake.nix"]
        case "Shell & Environment": return ["modules/home/shell-environment.nix", "home.nix"]
        case "AI Agents": return ["modules/home/ai-agents.nix", "home.nix"]
        case "Security & Secrets": return ["modules/darwin/security-secrets.nix", "flake.nix"]
        default: return []
        }
    }

    private var fileURL: URL? {
        let repo = Paths().repoDir
        return candidates
            .map { repo.appending(path: $0) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private var isDirty: Bool { text != savedText }

    var body: some View {
        VStack(spacing: 0) {
            if let fileURL {
                HStack(spacing: 10) {
                    Image(systemName: "doc.text")
                        .foregroundStyle(Theme.accent)
                    Text(fileURL.path.replacingOccurrences(of: Paths().repoDir.path + "/", with: ""))
                        .font(.system(.callout, design: .monospaced))
                        .lineLimit(1)
                        .textSelection(.enabled)
                    Spacer(minLength: 0)
                    Button("Format", systemImage: "text.alignleft", action: format)
                        .disabled(formatting)
                        .help("Save and format this Nix file")
                    Button("Save", systemImage: "square.and.arrow.down", action: save)
                        .disabled(!isDirty || formatting)
                        .help("Save source file")
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
                Divider().opacity(0.5)
                NixCodeEditor(text: $text)
                    .onAppear { load(fileURL) }
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 8)
                }
            } else {
                ContentUnavailableView(
                    "Source file unavailable",
                    systemImage: "doc.questionmark",
                    description: Text("No configured source module was found for \(area.id).")
                )
            }
        }
    }

    private func load(_ url: URL) {
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            text = content
            savedText = content
            error = nil
        } catch {
            self.error = "Could not read source: \(error.localizedDescription)"
        }
    }

    private func save() {
        guard let url = fileURL else { return }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            savedText = text
            error = nil
            onSave()
        } catch {
            self.error = "Could not save source: \(error.localizedDescription)"
        }
    }

    private func format() {
        guard let url = fileURL else { return }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            formatting = true
            error = nil
            Task {
                let formatted = await NixFormat.format(file: url, repoDir: Paths().repoDir) { _ in }
                formatting = false
                if formatted {
                    load(url)
                    onSave()
                } else {
                    error = "No file-level Nix formatter found."
                }
            }
        } catch {
            self.error = "Could not save source: \(error.localizedDescription)"
        }
    }
}

/// AppKit's text system gives the source pane syntax attributes without giving
/// up native editing, undo, find, or keyboard selection behavior.
private struct NixCodeEditor: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 480)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textContainerInset = NSSize(width: 24, height: 20)
        textView.delegate = context.coordinator
        textView.string = text
        NixSyntaxHighlight.apply(to: textView)

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = true
        scroll.backgroundColor = .textBackgroundColor
        scroll.documentView = textView
        context.coordinator.textView = textView
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.text = $text
        guard let textView = scroll.documentView as? NSTextView,
              textView.string != text else { return }
        let selection = textView.selectedRange()
        textView.string = text
        NixSyntaxHighlight.apply(to: textView)
        textView.setSelectedRange(NSRange(location: min(selection.location, (text as NSString).length), length: 0))
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        weak var textView: NSTextView?

        init(text: Binding<String>) { self.text = text }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            let selection = textView.selectedRange()
            NixSyntaxHighlight.apply(to: textView)
            text.wrappedValue = textView.string
            textView.setSelectedRange(selection)
        }
    }
}

private enum NixSyntaxHighlight {
    private static let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    private static let keyword = try! NSRegularExpression(pattern: #"\b(let|in|with|if|then|else|rec|inherit|assert|or|null|true|false)\b"#)
    private static let builtin = try! NSRegularExpression(pattern: #"\b(pkgs|lib|config|self|inputs|builtins)\b"#)
    private static let number = try! NSRegularExpression(pattern: #"\b\d+(?:\.\d+)?\b"#)
    private static let string = try! NSRegularExpression(pattern: #""(?:\\.|[^"\\])*""#)
    private static let comment = try! NSRegularExpression(pattern: #"(?m)#.*$"#)

    static func apply(to textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        let range = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.setAttributes([
            .font: font,
            .foregroundColor: NSColor.labelColor,
        ], range: range)
        apply(keyword, color: NSColor.systemPurple, to: storage, range: range)
        apply(builtin, color: NSColor.systemTeal, to: storage, range: range)
        apply(number, color: NSColor.systemBlue, to: storage, range: range)
        apply(string, color: NSColor.systemOrange, to: storage, range: range)
        apply(comment, color: NSColor.secondaryLabelColor, to: storage, range: range)
        storage.endEditing()
    }

    private static func apply(_ expression: NSRegularExpression, color: NSColor,
                              to storage: NSTextStorage, range: NSRange) {
        for match in expression.matches(in: storage.string, range: range) {
            storage.addAttribute(.foregroundColor, value: color, range: match.range)
        }
    }
}

/// A recipe card that opens a preview before any recipe content reaches chat.
private struct SectionRecipeCard: View {
    let recipe: Recipe
    let onSelect: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Theme.brandSoft).frame(width: 42, height: 42)
                    Image(systemName: recipe.symbol).font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
                VStack(alignment: .leading, spacing: 5) {
                    if recipe.featured {
                        Text("RECOMMENDED")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.5)
                            .foregroundStyle(Theme.accent)
                    }
                    Text(recipe.title)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text(recipe.summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(hover ? Color.white : Theme.accent)
                    .frame(width: 28, height: 28)
                    .background(hover ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.brandSoft),
                                in: Circle())
            }
            .padding(16)
            .frame(minHeight: 104)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                hover ? AnyShapeStyle(Theme.brandSoft) : AnyShapeStyle(Color.primary.opacity(0.03)),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(recipe.featured ? Theme.accent : Theme.accent.opacity(hover ? 0.65 : 0.24))
                    .frame(width: 3)
                    .padding(.vertical, 14)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(hover ? Theme.accent.opacity(0.45) : Color.primary.opacity(0.10))
            )
            .shadow(color: .black.opacity(hover ? 0.07 : 0), radius: 6, y: 3)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.14), value: hover)
    }
}

/// A deliberate review point between browsing a recipe and sending it through
/// the conversation. Adding the recipe here is the explicit approval.
struct RecipePreviewSheet: View {
    let recipe: Recipe
    let onAddToChat: () -> Void
    let onEditPrompt: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                        .fill(Theme.brandSoft)
                        .frame(width: 42, height: 42)
                    Image(systemName: recipe.symbol)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Theme.accent)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(recipe.title).font(.title3.weight(.semibold))
                    Text(recipe.section).font(.caption.weight(.medium)).foregroundStyle(Theme.accent)
                    Text(recipe.summary).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Markdown(text: recipe.body)
                    if let guide = recipe.guide, !guide.isEmpty {
                        Divider()
                        Label("Guide", systemImage: "book.closed")
                            .font(.headline)
                        Markdown(text: guide)
                    }
                    if let source = recipe.source, !source.isEmpty {
                        Label(source, systemImage: "link")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            HStack {
                Text("Adding sends this recipe to the selected agent.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", action: dismiss.callAsFunction)
                    .keyboardShortcut(.cancelAction)
                if let onEditPrompt {
                    Button("Edit prompt") {
                        onEditPrompt()
                        dismiss()
                    }
                }
                Button("Add to chat") {
                    onAddToChat()
                    dismiss()
                }
                .buttonStyle(.brandCompact)
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(minWidth: 620, idealWidth: 700, minHeight: 560, idealHeight: 680)
    }
}

// MARK: - Featured prompt card

struct FeaturedRecipeCard: View {
    let recipe: Recipe
    let action: () -> Void

    var body: some View {
        SectionRecipeCard(recipe: recipe, onSelect: action)
    }
}

// MARK: - Terminal

/// A dark, self-contained log terminal with a titlebar. Shown on demand.
// MARK: - Pipeline step

/// One stage of the build → apply → format → commit pipeline, as a chat entry
/// with its own embedded terminal. Expanded while running (so its live output is
/// visible), auto-collapses on success to keep the transcript tidy, and stays
/// open on failure so the error is right there.
private struct StepRow: View {
    let step: ChatMessage
    @State private var expanded = true

    private var accent: Color {
        switch step.state {
        case .running: return Theme.accent
        case .ok: return Color(red: 0.3, green: 0.72, blue: 0.4)
        case .failed: return Color(red: 0.85, green: 0.3, blue: 0.3)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
            } label: {
                HStack(spacing: 10) {
                    statusIcon
                    Text(step.text).font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 8)
                    if !step.lines.isEmpty {
                        Text("\(step.lines.count) lines")
                            .font(.caption2).foregroundStyle(.secondary)
                            .monospacedDigit()
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(step.lines.isEmpty)

            if expanded && !step.lines.isEmpty {
                Terminal(lines: step.lines, busy: step.state == .running)
                    .frame(minHeight: 90, maxHeight: 260)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                    .padding(.horizontal, 12).padding(.bottom, 12)
            }
        }
        .background(accent.opacity(0.06), in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .strokeBorder(accent.opacity(0.22)))
        .onChange(of: step.state) { _, s in
            // Tidy up once a stage succeeds; leave failures open.
            if s == .ok { withAnimation(.easeInOut(duration: 0.2)) { expanded = false } }
        }
    }

    @ViewBuilder private var statusIcon: some View {
        switch step.state {
        case .running:
            ProgressView().controlSize(.small)
        case .ok:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(accent)
        case .failed:
            Image(systemName: "xmark.circle.fill").foregroundStyle(accent)
        }
    }
}

struct Terminal: View {
    let lines: [String]
    var busy = false
    /// What's currently running (e.g. "Applying changes…"), shown in the
    /// titlebar in place of the generic "running…" label while busy.
    var activity: String = ""
    var onClear: (() -> Void)? = nil
    var onHide: (() -> Void)? = nil

    private let bg = Color(red: 0.085, green: 0.086, blue: 0.105)

    var body: some View {
        VStack(spacing: 0) {
            titlebar
            Divider().overlay(Color.white.opacity(0.08))
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        if lines.isEmpty {
                            Text("Ready.").font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.3))
                        }
                        ForEach(Array(lines.enumerated()), id: \.offset) { i, l in
                            Text(l).font(.system(.caption, design: .monospaced))
                                .fontWeight(l.hasPrefix("==>") ? .semibold : .regular)
                                .foregroundStyle(color(for: l)).id(i)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                }
                .scrollIndicators(.visible)
                // No animation here: a single burst of output can append dozens
                // of lines at once, and animating every one of those steps made
                // the terminal visibly lag behind the actual log.
                .onChange(of: lines.count) { _, _ in
                    if let last = lines.indices.last { proxy.scrollTo(last, anchor: .bottom) }
                }
            }
        }
        .background(bg)
    }

    private var titleText: String {
        if busy { return activity.isEmpty ? "running…" : activity }
        return "log"
    }

    private var titlebar: some View {
        HStack(spacing: 9) {
            if busy {
                ProgressView().controlSize(.mini).tint(.white)
            } else {
                Image(systemName: "terminal")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
            }
            Text(titleText)
                .font(.system(.caption2, design: .monospaced).weight(busy ? .semibold : .regular))
                .foregroundStyle(.white.opacity(busy ? 0.85 : 0.5))
                .lineLimit(1)
                .animation(nil, value: titleText)
            Spacer(minLength: 8)
            if let onClear {
                Button(action: onClear) { Image(systemName: "trash") }
                    .buttonStyle(.plain).foregroundStyle(.white.opacity(0.45))
                    .help("Clear log").disabled(lines.isEmpty)
            }
            if let onHide {
                Button(action: onHide) { Image(systemName: "chevron.down") }
                    .buttonStyle(.plain).foregroundStyle(.white.opacity(0.45))
                    .help("Hide")
            }
        }
        .font(.caption)
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(Color.white.opacity(0.05))
    }

    /// Light syntax coloring for common log signals.
    private func color(for line: String) -> Color {
        let l = line.lowercased()
        if l.contains("error") || l.contains("failed") || l.contains("failure") {
            return Color(red: 1, green: 0.45, blue: 0.42)
        }
        if l.contains("succeeded") || l.contains("complete") || l.contains("applied") || l.contains("installed") {
            return Color(red: 0.45, green: 0.9, blue: 0.5)
        }
        if l.hasPrefix("==>") {
            return Color(red: 0.68, green: 0.62, blue: 1)
        }
        if l.hasPrefix("darwin-rebuild") || l.contains("building") || l.contains("→") {
            return Color(red: 0.55, green: 0.75, blue: 1)
        }
        return .white.opacity(0.82)
    }
}

// MARK: - Agent transcript

/// Renders an agent message: tool calls (`› Tool detail`) become tidy chips,
/// errors/warnings get colored rows, and everything else is treated as Markdown
/// (headings, lists, emphasis, inline + fenced code) rather than flat prose.
private struct AgentTranscript: View {
    let text: String

    /// A run of the message: a special line (tool/error/warning) that keeps its
    /// bespoke rendering, or a chunk of prose rendered as Markdown.
    private enum Segment { case tool(String), error(String), warning(String), markdown(String) }

    /// Split the streamed text into segments, coalescing consecutive prose lines
    /// into one Markdown chunk so block constructs (lists, code fences) survive.
    private var segments: [(Int, Segment)] {
        var out: [Segment] = []
        var buf: [String] = []
        func flush() {
            let joined = buf.joined(separator: "\n").trimmingCharacters(in: .newlines)
            if !joined.isEmpty { out.append(.markdown(joined)) }
            buf = []
        }
        for line in text.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("› ") { flush(); out.append(.tool(String(line.dropFirst(2)))) }
            else if t.hasPrefix("✗") { flush(); out.append(.error(t)) }
            else if t.hasPrefix("⚠︎") || t.hasPrefix("⚠") { flush(); out.append(.warning(t)) }
            else { buf.append(line) }
        }
        flush()
        return Array(out.enumerated())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(segments, id: \.0) { _, seg in
                switch seg {
                case .tool(let s): toolChip(s)
                case .error(let s):
                    marker(s, symbol: "xmark.circle.fill", tint: Color(red: 0.85, green: 0.3, blue: 0.3))
                case .warning(let s):
                    marker(s, symbol: "exclamationmark.triangle.fill", tint: .orange)
                case .markdown(let s): Markdown(text: s)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// `s` is "Tool  detail" — split into a name and its argument summary.
    private func toolChip(_ s: String) -> some View {
        let parts = s.split(separator: " ", maxSplits: 1).map(String.init)
        let name = parts.first ?? s
        let detail = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
        return HStack(spacing: 7) {
            Image(systemName: toolIcon(name))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 13)
            Text(name)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.accent)
            if !detail.isEmpty {
                Text(detail)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 4)
        .frame(maxWidth: 560, alignment: .leading)
        .background(Theme.accent.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func marker(_ text: String, symbol: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: symbol).font(.caption2).foregroundStyle(tint)
            Text(text.trimmingCharacters(in: CharacterSet(charactersIn: "✗⚠︎⚠ ")))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(tint)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func toolIcon(_ name: String) -> String {
        switch name.lowercased() {
        case "read": return "doc.text"
        case "write", "edit", "multiedit", "notebookedit": return "pencil"
        case "bash": return "terminal"
        case "grep", "glob", "search": return "magnifyingglass"
        case "webfetch", "websearch": return "globe"
        case "task": return "person.2"
        case "todowrite": return "checklist"
        default: return "wrench.and.screwdriver"
        }
    }
}

// MARK: - Markdown

/// A lightweight block-level Markdown renderer for agent prose: headings, bullet
/// and ordered lists, blockquotes, horizontal rules, fenced code blocks, and
/// paragraphs. Inline emphasis / inline code / links are handled by SwiftUI's
/// own `AttributedString(markdown:)`. Deliberately small — enough for the kind
/// of answers the agent writes, not a full CommonMark implementation.
struct Markdown: View {
    let text: String
    var fontScale: CGFloat = 1

    private struct ListItem { let level: Int; let marker: String?; let text: String }

    private enum Block {
        case heading(level: Int, text: String)
        case list([ListItem])
        case table(header: [String], rows: [[String]])
        case quote(String)
        case code(String)
        case rule
        case paragraph(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, b in
                view(for: b)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    // MARK: parsing

    private var blocks: [Block] {
        var out: [Block] = []
        let lines = text.components(separatedBy: "\n")
        var para: [String] = []
        var list: [ListItem] = []
        func flushPara() {
            let s = para.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty { out.append(.paragraph(s)) }
            para = []
        }
        func flushList() {
            if !list.isEmpty { out.append(.list(list)) }
            list = []
        }
        var i = 0
        while i < lines.count {
            let line = lines[i]
            let t = line.trimmingCharacters(in: .whitespaces)
            let indent = line.prefix(while: { $0 == " " }).count

            if t.hasPrefix("```") {                    // fenced code block
                flushPara(); flushList()
                var code: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[i]); i += 1
                }
                out.append(.code(code.joined(separator: "\n")))
                i += 1                                  // consume closing fence (if any)
                continue
            }
            if isTableHeader(line, separator: i + 1 < lines.count ? lines[i + 1] : nil) {
                flushPara(); flushList()
                let header = tableCells(line)
                var rows: [[String]] = []
                i += 2 // Header plus the Markdown separator row.
                while i < lines.count {
                    let row = lines[i]
                    guard row.contains("|"), !row.trimmingCharacters(in: .whitespaces).isEmpty else { break }
                    let cells = tableCells(row)
                    guard cells.count == header.count else { break }
                    rows.append(cells)
                    i += 1
                }
                out.append(.table(header: header, rows: rows))
                continue
            }
            if t.isEmpty { flushPara(); flushList() }
            else if t == "---" || t == "***" || t == "___" { flushPara(); flushList(); out.append(.rule) }
            else if let h = heading(t) { flushPara(); flushList(); out.append(.heading(level: h.0, text: h.1)) }
            else if t.hasPrefix("- ") || t.hasPrefix("* ") {
                flushPara()
                list.append(ListItem(level: indent / 2, marker: nil, text: String(t.dropFirst(2))))
            } else if let o = ordered(t) {
                flushPara()
                list.append(ListItem(level: indent / 2, marker: o.0, text: o.1))
            } else if t.hasPrefix("> ") { flushPara(); flushList(); out.append(.quote(String(t.dropFirst(2)))) }
            else { flushList(); para.append(line) }
            i += 1
        }
        flushPara(); flushList()
        return out
    }

    private func heading(_ t: String) -> (Int, String)? {
        var n = 0
        for c in t { if c == "#" { n += 1 } else { break } }
        guard n > 0, n <= 6, t.count > n,
              t[t.index(t.startIndex, offsetBy: n)] == " " else { return nil }
        return (n, String(t.dropFirst(n + 1)))
    }

    private func ordered(_ t: String) -> (String, String)? {
        guard let dot = t.firstIndex(of: ".") else { return nil }
        let num = t[t.startIndex..<dot]
        let after = t.index(after: dot)
        guard !num.isEmpty, num.allSatisfy(\.isNumber),
              after < t.endIndex, t[after] == " " else { return nil }
        return (String(num) + ".", String(t[t.index(after: after)...]))
    }

    private func isTableHeader(_ header: String, separator: String?) -> Bool {
        guard header.contains("|"), let separator, separator.contains("|") else { return false }
        let headings = tableCells(header)
        let rules = tableCells(separator)
        guard headings.count >= 2, headings.count == rules.count else { return false }
        return rules.allSatisfy { rule in
            let core = rule.trimmingCharacters(in: CharacterSet(charactersIn: ":- "))
            return core.isEmpty && rule.contains("-")
        }
    }

    private func tableCells(_ line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") { trimmed.removeFirst() }
        if trimmed.hasSuffix("|") { trimmed.removeLast() }
        return trimmed.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    // MARK: rendering

    @ViewBuilder private func view(for block: Block) -> some View {
        switch block {
        case .heading(let level, let text):
            inline(text)
                .font(headingFont(level)).fontWeight(.bold)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, level <= 2 ? 6 : 2)
        case .list(let items):
            VStack(alignment: .leading, spacing: 7 * fontScale) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 8 * fontScale) {
                        Text(item.marker ?? "•")
                            .foregroundStyle(Theme.accent).font(bodyFont)
                            .monospacedDigit()
                        inline(item.text).font(bodyFont).lineSpacing(2 * fontScale)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, CGFloat(item.level) * 18 * fontScale)
                }
            }
        case .table(let header, let rows):
            ScrollView(.horizontal, showsIndicators: false) {
                Grid(alignment: .leading, horizontalSpacing: 16 * fontScale, verticalSpacing: 8 * fontScale) {
                    GridRow {
                        ForEach(Array(header.enumerated()), id: \.offset) { _, cell in
                            inline(cell)
                                .font(bodyFont.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 90 * fontScale, alignment: .leading)
                        }
                    }
                    Divider().gridCellColumns(max(header.count, 1))
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        GridRow {
                            ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                                inline(cell)
                                    .font(bodyFont)
                                    .frame(minWidth: 90 * fontScale, alignment: .leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(10 * fontScale)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.035),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08)))
        case .quote(let text):
            HStack(spacing: 10 * fontScale) {
                RoundedRectangle(cornerRadius: 1.5).fill(Theme.accent.opacity(0.4)).frame(width: 3)
                inline(text).font(bodyFont).foregroundStyle(.secondary).lineSpacing(2 * fontScale)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 2)
            }
        case .code(let code):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code).font(.system(size: 11 * fontScale, design: .monospaced))
                    .padding(10 * fontScale).textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.05),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08)))
        case .rule:
            Divider().padding(.vertical, 2)
        case .paragraph(let text):
            inline(text).font(bodyFont).lineSpacing(3 * fontScale)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Inline emphasis / code / links via SwiftUI's own Markdown parser, falling
    /// back to the raw string when it can't parse (e.g. an unterminated `**`).
    private func inline(_ s: String) -> Text {
        let opts = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let attr = try? AttributedString(markdown: s, options: opts) {
            return Text(attr)
        }
        return Text(s)
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .system(size: 20 * fontScale)
        case 2: return .system(size: 14 * fontScale)
        default: return .system(size: 13 * fontScale)
        }
    }

    private var bodyFont: Font {
        .system(size: 13 * fontScale)
    }
}
