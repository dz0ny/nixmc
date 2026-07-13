import SwiftUI

/// Native Settings window. Values are UserDefaults-backed by `AppSettings` and
/// take effect without relaunching the app.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsPane()
                .tabItem { Label("General", systemImage: "gearshape") }
            SyncSettingsPane()
                .tabItem { Label("Sync", systemImage: "arrow.triangle.branch") }
            TeamSettingsPane()
                .tabItem { Label("My Team", systemImage: "person.3") }
            IntelligenceSettingsPane()
                .tabItem { Label("AI", systemImage: "sparkles") }
            UpdateSettingsPane()
                .tabItem { Label("Updates", systemImage: "arrow.triangle.2.circlepath") }
            AppearanceSettingsPane()
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
        }
        .frame(width: 520)
        .tint(Theme.accent)
    }
}

private struct TeamSettingsPane: View {
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var teamRecipes = TeamRecipeStore.shared

    var body: some View {
        Form {
            Section {
                TextField("GitHub repo", text: $settings.teamRecipesRepository,
                          prompt: Text("company/nixmc-recipes"))
                    .autocorrectionDisabled()
                    .textContentType(.URL)

                Picker("Connect over", selection: $settings.teamRecipesUseSSH) {
                    Text("SSH").tag(true)
                    Text("HTTPS").tag(false)
                }
                .pickerStyle(.segmented)

                Button {
                    teamRecipes.synchronize(repository: settings.teamRecipesRepository,
                                            useSSH: settings.teamRecipesUseSSH)
                } label: {
                    Label(teamRecipes.state == .syncing ? "Fetching…" : "Fetch Now",
                          systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(settings.teamRecipesRepository.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || teamRecipes.state == .syncing)
            } header: {
                Text("Shared Recipe Repository")
            } footer: {
                Text("Clone a repository of Markdown recipes shared by your team. nixmc stores this managed checkout separately from your configuration repository, fetches hourly, and refreshes My Team on open when the checkout is older than one minute.")
            }

            Section("Managed Checkout") {
                LabeledContent("Location") {
                    Text(teamRecipes.directory.path)
                        .font(.callout.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                LabeledContent("Available recipes", value: "\(teamRecipes.recipes.count)")
                LabeledContent("Last fetched", value: lastFetched)

                switch teamRecipes.state {
                case .idle: EmptyView()
                case .syncing:
                    LabeledContent("Status") { ProgressView().controlSize(.small) }
                case .ready(let message):
                    Label(message, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .failed(let message):
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .formStyle(.grouped)
        .frame(height: 410)
        .onAppear { teamRecipes.reload() }
    }

    private var lastFetched: String {
        teamRecipes.lastFetch?.formatted(.relative(presentation: .named)) ?? "Never"
    }
}

private struct GeneralSettingsPane: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var settings: AppSettings
    @State private var confirmReset = false

    private var selectableAgents: [AgentCLI] {
        app.agents.filter { $0.id == "claude" || $0.id == "codex" || $0.id == "ollama-aider" || $0.id == "kimi-aider" }
    }

    var body: some View {
        Form {
            Section("Agent") {
                if selectableAgents.isEmpty {
                    LabeledContent("Coding agent", value: "No supported coding agent found")
                } else {
                    Picker("Coding agent", selection: selectedAgentID) {
                        ForEach(selectableAgents) { agent in
                            Text(agent.displayName).tag(agent.id)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                TextField("Extra instructions", text: $settings.customInstructions, axis: .vertical)
                    .lineLimit(2...4)

                if selectedAgentID.wrappedValue == "ollama-aider" {
                    TextField("Ollama coding model", text: $settings.ollamaAiderModel,
                              prompt: Text("qwen2.5-coder:7b"))
                        .autocorrectionDisabled()
                    Text("Requires Ollama running locally and this model to be pulled.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Workflow") {
                Toggle("Build automatically after edits", isOn: $settings.autoBuild)
                Toggle("Format Nix files after edits", isOn: $settings.autoFormat)
                Toggle("Review apply output with the agent", isOn: $settings.reviewApplyOutput)
            }

            Section {
                Button("Reset All Settings", role: .destructive) { confirmReset = true }
            }
        }
        .formStyle(.grouped)
        .frame(height: 370)
        .onAppear(perform: normalizeSelectedAgent)
        .confirmationDialog("Reset all settings?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) {
                settings.resetToDefaults()
                normalizeSelectedAgent()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var selectedAgentID: Binding<String> {
        Binding(
            get: { app.selectedAgent?.id ?? selectableAgents.first?.id ?? "" },
            set: { app.selectAgent(id: $0) })
    }

    private func normalizeSelectedAgent() {
        guard let fallback = selectableAgents.first,
              !selectableAgents.contains(where: { $0.id == app.selectedAgent?.id }) else { return }
        app.selectAgent(id: fallback.id)
    }
}

private struct SyncSettingsPane: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var settings: AppSettings
    /// `origin` already configured on the repo (e.g. a hand-cloned dotfiles
    /// repo), offered as a one-click fill when the setting is empty.
    @State private var detectedOrigin: String?

    var body: some View {
        Form {
            Section {
                TextField("GitHub repo", text: $settings.gitRemoteURL,
                          prompt: Text("you/dotfiles"))
                    .autocorrectionDisabled()
                    .textContentType(.URL)

                Picker("Connect over", selection: $settings.gitRemoteUseSSH) {
                    Text("SSH").tag(true)
                    Text("HTTPS").tag(false)
                }
                .pickerStyle(.segmented)
                .disabled(isFullURL)

                if !resolved.isEmpty {
                    LabeledContent("Remote") {
                        Text(resolved)
                            .font(.callout.monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                } else if settings.gitRemoteURL.isEmpty, let origin = detectedOrigin {
                    LabeledContent("Detected origin") {
                        HStack(spacing: 8) {
                            Text(origin)
                                .font(.callout.monospaced())
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .foregroundStyle(.secondary)
                            Button("Use") { settings.gitRemoteURL = origin }
                                .controlSize(.small)
                        }
                    }
                }
            } header: {
                Text("Remote")
            } footer: {
                Text("Enter a GitHub handle like **you/dotfiles**, or paste any full git URL. Pushes use your existing SSH keys or keychain credentials.")
            }

            Section {
                Toggle("Push after each commit", isOn: $settings.autoPush)
                    .disabled(resolved.isEmpty)

                Button {
                    app.pushNow()
                } label: {
                    Label("Push Now", systemImage: "arrow.up.circle")
                }
                .disabled(resolved.isEmpty || app.phase != .ready || app.busy)
                .help("Push the configuration history to the remote now")
            } header: {
                Text("Push")
            } footer: {
                Text("Every commit nixmc makes — applies and rollbacks — is pushed here, keeping your dotfiles repo in sync.")
            }
        }
        .formStyle(.grouped)
        .frame(height: 420)
        .onAppear(perform: detectOrigin)
    }

    private var resolved: String { settings.resolvedGitRemote }

    /// True when the input is already a full URL, so the SSH/HTTPS choice
    /// (which only shapes bare-handle expansion) doesn't apply.
    private var isFullURL: Bool {
        let trimmed = settings.gitRemoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && resolved == trimmed
    }

    /// Surface an `origin` the repo already has (git shell-out off the main
    /// actor — see the AppState convention).
    private func detectOrigin() {
        guard app.phase == .ready else { return }
        let repo = app.paths.repoDir
        Task {
            detectedOrigin = await Task.detached { Git.remoteURL(in: repo) }.value
        }
    }
}

private struct IntelligenceSettingsPane: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Form {
            Section("Generated Content") {
                Toggle("Summarize diffs", isOn: $settings.aiSummaries)
                Toggle("Draft commit messages", isOn: $settings.aiCommitMessages)
                Toggle("Keep the configuration guide updated", isOn: $settings.keepGuideUpdated)
            }
        }
        .formStyle(.grouped)
        .frame(height: 230)
    }
}

private struct UpdateSettingsPane: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Form {
            Section("Automatic Checks") {
                Toggle("Check for flake updates automatically", isOn: $settings.autoUpdateChecks)

                Picker("Frequency", selection: $settings.updateCadence) {
                    ForEach(UpdateCadence.allCases) { cadence in
                        Text(cadence.label).tag(cadence)
                    }
                }
                .disabled(!settings.autoUpdateChecks)

                Picker("Required idle time", selection: $settings.idleMinutes) {
                    Text("1 minute").tag(1)
                    Text("3 minutes").tag(3)
                    Text("5 minutes").tag(5)
                    Text("10 minutes").tag(10)
                }
                .disabled(!settings.autoUpdateChecks)
            }

            Section("Proposals") {
                Stepper(value: $settings.maxProposals, in: 1...10) {
                    LabeledContent("Maximum retained", value: "\(settings.maxProposals)")
                }

                LabeledContent("Last checked", value: lastChecked)

                Button {
                    app.checkForUpdatesNow()
                } label: {
                    Label("Check Now", systemImage: "arrow.clockwise")
                }
                .disabled(app.phase != .ready || app.updateChecking)
            }
        }
        .formStyle(.grouped)
        .frame(height: 390)
    }

    private var lastChecked: String {
        app.lastUpdateCheck?.formatted(.relative(presentation: .named)) ?? "Never"
    }
}

private struct AppearanceSettingsPane: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Form {
            Section("Window") {
                Picker("Appearance", selection: $settings.appearanceMode) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                LabeledContent("Help text size") {
                    HStack(spacing: 6) {
                        Button { app.decreaseHelpTextSize() } label: {
                            Image(systemName: "textformat.size.smaller")
                        }
                        .help("Decrease text size")

                        Button("Reset") { app.resetHelpTextSize() }
                            .help("Reset text size")

                        Button { app.increaseHelpTextSize() } label: {
                            Image(systemName: "textformat.size.larger")
                        }
                        .help("Increase text size")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            Section("Accent") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 68), spacing: 12)], spacing: 12) {
                    ForEach(Theme.palettes) { palette in
                        paletteButton(palette)
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .formStyle(.grouped)
        .frame(height: 390)
    }

    private func paletteButton(_ palette: ThemePalette) -> some View {
        let selected = settings.themeID == palette.id
        return Button {
            settings.themeID = palette.id
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [palette.start, palette.end],
                                             startPoint: .topLeading,
                                             endPoint: .bottomTrailing))
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 34, height: 34)
                .overlay(Circle().stroke(selected ? palette.accent : .clear, lineWidth: 2).padding(-3))

                Text(palette.name)
                    .font(.caption)
                    .foregroundStyle(.primary)
            }
            .frame(width: 62, height: 58)
        }
        .buttonStyle(.plain)
        .help("Use \(palette.name) accent")
    }
}
