import AppKit
import SwiftUI

// MARK: - Option enums

/// How the app window renders relative to the system appearance.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    /// nil = follow the system.
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

/// How often the background flake-update check considers itself due.
enum UpdateCadence: String, CaseIterable, Identifiable {
    case daily, weekly, monthly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        }
    }

    var seconds: TimeInterval {
        switch self {
        case .daily: return 24 * 3600
        case .weekly: return 7 * 24 * 3600
        case .monthly: return 30 * 24 * 3600
        }
    }
}

// MARK: - Store

/// Every user-tunable knob in the app, UserDefaults-backed with registered
/// (sensible) defaults. One shared instance: views observe it, and behavior
/// code reads it at the moment of use, so changes take effect immediately —
/// no relaunch. Surfaced in the Settings window (⌘,), one tab per part of
/// the app.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    // MARK: agent

    /// Binary name of the preferred agent CLI ("" = first detected).
    @Published var preferredAgentID: String { didSet { d.set(preferredAgentID, forKey: K.preferredAgent) } }
    /// Free-form guidance appended to every agent request (e.g. "prefer
    /// nixpkgs over Homebrew").
    @Published var customInstructions: String { didSet { d.set(customInstructions, forKey: K.customInstructions) } }
    /// Model tag served by local Ollama when using the Ollama + Aider agent.
    @Published var ollamaAiderModel: String { didSet { d.set(ollamaAiderModel, forKey: K.ollamaAiderModel) } }

    // MARK: pipeline

    /// Run `darwin-rebuild build` automatically after the agent edits. Off:
    /// edits wait as uncommitted changes until the user hits Build & Apply.
    @Published var autoBuild: Bool { didSet { d.set(autoBuild, forKey: K.autoBuild) } }
    /// Format .nix files (treefmt/nixfmt/…) after agent edits and before commits.
    @Published var autoFormat: Bool { didSet { d.set(autoFormat, forKey: K.autoFormat) } }
    /// Hand `darwin-rebuild switch` output back to the agent after an apply,
    /// so it can reflect renamed casks / deprecations in the config.
    @Published var reviewApplyOutput: Bool { didSet { d.set(reviewApplyOutput, forKey: K.reviewApplyOutput) } }

    // MARK: sync

    /// Git remote for the config (dotfiles) repo; "" = no remote sync. May be a
    /// bare GitHub handle (`you/dotfiles`) — resolved via `resolvedGitRemote`.
    /// Applied to `origin` at push time, so edits here affect the next push.
    @Published var gitRemoteURL: String { didSet { d.set(gitRemoteURL, forKey: K.gitRemoteURL) } }
    /// Expand a bare GitHub handle over SSH (`git@…`) rather than HTTPS.
    @Published var gitRemoteUseSSH: Bool { didSet { d.set(gitRemoteUseSSH, forKey: K.gitRemoteUseSSH) } }
    /// Push to the remote automatically after every commit nixmc makes.
    /// Inert until a remote URL is set.
    @Published var autoPush: Bool { didSet { d.set(autoPush, forKey: K.autoPush) } }

    // MARK: team recipes

    /// Separate repository containing hand-curated Markdown recipes shared by
    /// a team. It is checked out under ~/.nixmc, never in the config flake.
    @Published var teamRecipesRepository: String { didSet { d.set(teamRecipesRepository, forKey: K.teamRecipesRepository) } }
    @Published var teamRecipesUseSSH: Bool { didSet { d.set(teamRecipesUseSSH, forKey: K.teamRecipesUseSSH) } }

    /// The `gitRemoteURL` setting resolved to a real clone URL ("" = no sync).
    var resolvedGitRemote: String { Git.normalizeRemote(gitRemoteURL, ssh: gitRemoteUseSSH) }

    // MARK: intelligence

    /// Plain-English "What changed" summaries in the diff sheets.
    @Published var aiSummaries: Bool { didSet { d.set(aiSummaries, forKey: K.aiSummaries) } }
    /// Draft the commit message from the diff (falls back to the request text).
    @Published var aiCommitMessages: Bool { didSet { d.set(aiCommitMessages, forKey: K.aiCommitMessages) } }
    /// Surgically refresh GUIDE.md when an apply touches something it describes.
    @Published var keepGuideUpdated: Bool { didSet { d.set(keepGuideUpdated, forKey: K.keepGuideUpdated) } }

    // MARK: updates

    /// Master switch for the background flake-update check.
    @Published var autoUpdateChecks: Bool { didSet { d.set(autoUpdateChecks, forKey: K.autoUpdateChecks) } }
    @Published var updateCadence: UpdateCadence { didSet { d.set(updateCadence.rawValue, forKey: K.updateCadence) } }
    /// How long the user must be away from mouse/keyboard before a check fires.
    @Published var idleMinutes: Int { didSet { d.set(idleMinutes, forKey: K.idleMinutes) } }
    /// Cap on parked update proposals; the oldest beyond it are discarded.
    @Published var maxProposals: Int { didSet { d.set(maxProposals, forKey: K.maxProposals) } }

    // MARK: appearance

    @Published var appearanceMode: AppearanceMode {
        didSet {
            d.set(appearanceMode.rawValue, forKey: K.appearanceMode)
            applyAppearance()
        }
    }
    /// Accent palette id (see `Theme.palettes`).
    @Published var themeID: String {
        didSet {
            d.set(themeID, forKey: K.themeID)
            Theme.apply(id: themeID)
        }
    }

    var idleSeconds: TimeInterval { TimeInterval(idleMinutes) * 60 }

    /// Push the appearance override onto the app (nil = follow the system).
    /// Called at launch (AppDelegate) and whenever the mode changes.
    func applyAppearance() {
        NSApplication.shared.appearance = appearanceMode.nsAppearance
    }

    /// Back to the registered defaults; the didSets persist and re-apply
    /// theme/appearance as they fire.
    func resetToDefaults() {
        preferredAgentID = ""
        customInstructions = ""
        ollamaAiderModel = "qwen2.5-coder:7b"
        autoBuild = true
        autoFormat = true
        reviewApplyOutput = true
        gitRemoteURL = ""
        gitRemoteUseSSH = true
        autoPush = true
        teamRecipesRepository = ""
        teamRecipesUseSSH = true
        aiSummaries = true
        aiCommitMessages = true
        keepGuideUpdated = true
        autoUpdateChecks = true
        updateCadence = .weekly
        idleMinutes = 3
        maxProposals = 5
        appearanceMode = .system
        themeID = Theme.defaultPaletteID
    }

    // MARK: plumbing

    private enum K {
        static let preferredAgent = "preferredAgent"
        static let customInstructions = "agentInstructions"
        static let ollamaAiderModel = "ollamaAiderModel"
        static let autoBuild = "autoBuild"
        static let autoFormat = "autoFormat"
        static let reviewApplyOutput = "reviewApplyOutput"
        static let gitRemoteURL = "gitRemoteURL"
        static let gitRemoteUseSSH = "gitRemoteUseSSH"
        static let autoPush = "autoPush"
        static let teamRecipesRepository = "teamRecipesRepository"
        static let teamRecipesUseSSH = "teamRecipesUseSSH"
        static let aiSummaries = "aiSummaries"
        static let aiCommitMessages = "aiCommitMessages"
        static let keepGuideUpdated = "keepGuideUpdated"
        static let autoUpdateChecks = "autoUpdateChecks"
        static let updateCadence = "updateCadence"
        static let idleMinutes = "updateIdleMinutes"
        static let maxProposals = "maxUpdateProposals"
        static let appearanceMode = "appearanceMode"
        static let themeID = "themeID"
    }

    private let d: UserDefaults

    init(defaults: UserDefaults = .standard) {
        d = defaults
        d.register(defaults: [
            K.preferredAgent: "",
            K.customInstructions: "",
            K.ollamaAiderModel: "qwen2.5-coder:7b",
            K.autoBuild: true,
            K.autoFormat: true,
            K.reviewApplyOutput: true,
            K.gitRemoteURL: "",
            K.gitRemoteUseSSH: true,
            K.autoPush: true,
            K.teamRecipesRepository: "",
            K.teamRecipesUseSSH: true,
            K.aiSummaries: true,
            K.aiCommitMessages: true,
            K.keepGuideUpdated: true,
            K.autoUpdateChecks: true,
            K.updateCadence: UpdateCadence.weekly.rawValue,
            K.idleMinutes: 3,
            K.maxProposals: 5,
            K.appearanceMode: AppearanceMode.system.rawValue,
            K.themeID: Theme.defaultPaletteID,
        ])
        preferredAgentID = d.string(forKey: K.preferredAgent) ?? ""
        customInstructions = d.string(forKey: K.customInstructions) ?? ""
        ollamaAiderModel = d.string(forKey: K.ollamaAiderModel) ?? "qwen2.5-coder:7b"
        autoBuild = d.bool(forKey: K.autoBuild)
        autoFormat = d.bool(forKey: K.autoFormat)
        reviewApplyOutput = d.bool(forKey: K.reviewApplyOutput)
        gitRemoteURL = d.string(forKey: K.gitRemoteURL) ?? ""
        gitRemoteUseSSH = d.bool(forKey: K.gitRemoteUseSSH)
        autoPush = d.bool(forKey: K.autoPush)
        teamRecipesRepository = d.string(forKey: K.teamRecipesRepository) ?? ""
        teamRecipesUseSSH = d.bool(forKey: K.teamRecipesUseSSH)
        aiSummaries = d.bool(forKey: K.aiSummaries)
        aiCommitMessages = d.bool(forKey: K.aiCommitMessages)
        keepGuideUpdated = d.bool(forKey: K.keepGuideUpdated)
        autoUpdateChecks = d.bool(forKey: K.autoUpdateChecks)
        updateCadence = UpdateCadence(rawValue: d.string(forKey: K.updateCadence) ?? "") ?? .weekly
        idleMinutes = d.integer(forKey: K.idleMinutes)
        maxProposals = d.integer(forKey: K.maxProposals)
        appearanceMode = AppearanceMode(rawValue: d.string(forKey: K.appearanceMode) ?? "") ?? .system
        themeID = d.string(forKey: K.themeID) ?? Theme.defaultPaletteID
        // didSet doesn't fire during init — set the palette explicitly so the
        // first render already uses the persisted theme.
        Theme.apply(id: themeID)
    }
}
