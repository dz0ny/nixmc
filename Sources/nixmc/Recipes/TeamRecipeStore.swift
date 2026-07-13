import Foundation

/// Keeps a separately managed checkout of a team's curated recipe catalog.
/// It intentionally lives outside the nix-darwin flake so syncing recipes can
/// never alter the user's configuration Git history.
@MainActor
final class TeamRecipeStore: ObservableObject {
    static let shared = TeamRecipeStore()

    enum SyncState: Equatable {
        case idle
        case syncing
        case ready(String)
        case failed(String)
    }

    @Published private(set) var recipes: [Recipe] = []
    /// Repository-authored companion documentation, shown as-is in My Team.
    @Published private(set) var guide: String?
    @Published private(set) var state: SyncState = .idle
    @Published private(set) var lastFetch: Date?

    let directory: URL
    private var lastRepository = ""
    private var automaticFetchTask: Task<Void, Never>?

    init(fileManager: FileManager = .default) {
        directory = fileManager.homeDirectoryForCurrentUser
            .appending(path: ".nixmc/team-recipes", directoryHint: .isDirectory)
        lastFetch = UserDefaults.standard.object(forKey: "teamRecipesLastFetch") as? Date
        lastRepository = UserDefaults.standard.string(forKey: "teamRecipesLastRepository") ?? ""
        reload()
    }

    func reload() {
        recipes = RecipeCatalog.load(from: directory, sectionOverride: "My Team", idPrefix: "team:") ?? []
        guide = try? String(contentsOf: directory.appending(path: "GUIDE.md"), encoding: .utf8)
    }

    func synchronize(repository: String, useSSH: Bool) {
        let remote = Git.normalizeRemote(repository, ssh: useSSH)
        guard !remote.isEmpty else {
            state = .failed("Enter a repository before syncing.")
            return
        }

        let directoryPath = directory.path
        state = .syncing
        Task {
            let result = await Task.detached { () -> (success: Bool, message: String) in
                let manager = FileManager.default
                let directory = URL(fileURLWithPath: directoryPath, isDirectory: true)
                do {
                    if manager.fileExists(atPath: directory.appending(path: ".git").path) {
                        let existing = try Shell.run("/usr/bin/git", ["-C", directoryPath, "remote", "get-url", "origin"])
                        if existing.ok, existing.trimmedOut != remote {
                            try manager.removeItem(at: directory)
                        }
                    } else if manager.fileExists(atPath: directoryPath) {
                        try manager.removeItem(at: directory)
                    }

                    if manager.fileExists(atPath: directory.path) {
                        let pull = try Shell.run("/usr/bin/git", ["-C", directoryPath, "pull", "--ff-only"])
                        guard pull.ok else { return (false, pull.stderr.isEmpty ? pull.stdout : pull.stderr) }
                    } else {
                        try manager.createDirectory(at: directory.deletingLastPathComponent(), withIntermediateDirectories: true)
                        let clone = try Shell.run("/usr/bin/git", ["clone", "--depth", "1", remote, directoryPath])
                        guard clone.ok else { return (false, clone.stderr.isEmpty ? clone.stdout : clone.stderr) }
                    }
                    let count = RecipeCatalog.load(from: directory, sectionOverride: "My Team", idPrefix: "team:")?.count ?? 0
                    return (true, "Synced \(count) team recipe\(count == 1 ? "" : "s").")
                } catch {
                    return (false, error.localizedDescription)
                }
            }.value

            if result.success {
                reload()
                lastFetch = .now
                lastRepository = remote
                UserDefaults.standard.set(lastFetch, forKey: "teamRecipesLastFetch")
                UserDefaults.standard.set(lastRepository, forKey: "teamRecipesLastRepository")
                state = .ready(result.message)
            } else {
                state = .failed(result.message.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
    }

    /// Avoid repeated network work while navigating. A changed repository
    /// always fetches immediately, regardless of the recent-fetch window.
    func fetchIfNeeded(maxAge: TimeInterval) {
        let settings = AppSettings.shared
        let remote = Git.normalizeRemote(settings.teamRecipesRepository, ssh: settings.teamRecipesUseSSH)
        guard !remote.isEmpty, state != .syncing else { return }
        if remote == lastRepository,
           let lastFetch,
           Date.now.timeIntervalSince(lastFetch) < maxAge {
            return
        }
        synchronize(repository: settings.teamRecipesRepository, useSSH: settings.teamRecipesUseSSH)
    }

    /// User-initiated refreshes always contact the configured remote.
    func fetchNow() {
        let settings = AppSettings.shared
        synchronize(repository: settings.teamRecipesRepository, useSSH: settings.teamRecipesUseSSH)
    }

    func startAutomaticFetch() {
        guard automaticFetchTask == nil else { return }
        automaticFetchTask = Task { [weak self] in
            guard let self else { return }
            self.fetchIfNeeded(maxAge: 3600)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3600))
                guard !Task.isCancelled else { return }
                self.fetchIfNeeded(maxAge: 3600)
            }
        }
    }
}
