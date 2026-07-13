import Foundation

/// One parked flake update: a committed branch (kept alive by its worktree)
/// plus the metadata the sidebar and detail pane need. Produced on the
/// configured cadence by `UpdatePipeline`, applied or dismissed by the user.
struct UpdateProposal: Codable, Identifiable, Equatable, Sendable {
    enum BuildStatus: String, Codable, Sendable { case unverified, ok, failed }

    let id: String            // "yyyy-MM-dd-HHmmss" — branch- and directory-safe
    let createdAt: Date
    let branch: String        // "nixmc/update/<id>"
    let baseCommit: String    // full sha of repo HEAD when the check ran
    let tipCommit: String     // full sha of the update commit on the branch
    let diffHash: String      // SHA-256 of Git.diff(base, tip) — dedupe key
    var title: String
    var buildStatus: BuildStatus
    /// Last lines of a failed verify build, for the detail pane.
    var buildLogTail: [String]?
    var worktreePath: String
}

/// Everything the Updates section persists, in one JSON file.
struct UpdatesStore: Codable, Sendable {
    /// When the last *successful* check finished (also "no changes" / duplicate
    /// outcomes). Failed checks don't advance it, so they retry next tick.
    var lastChecked: Date?
    var proposals: [UpdateProposal] = []

    init() {}

    /// Tolerant decode, like `HomebrewData`: a missing key never throws.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lastChecked = try c.decodeIfPresent(Date.self, forKey: .lastChecked)
        proposals = try c.decodeIfPresent([UpdateProposal].self, forKey: .proposals) ?? []
    }
}

/// Disk layout for update proposals: metadata JSON plus one worktree directory
/// per proposal, all under Application Support (not Caches — proposals must
/// survive a cache purge).
enum UpdatesStorage {
    static let branchPrefix = "nixmc/update/"

    /// ~/Library/Application Support/nixmc/updates
    static var rootDir: URL {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("nixmc/updates", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var storeURL: URL { rootDir.appendingPathComponent("proposals.json") }

    static func worktreeDir(id: String) -> URL {
        rootDir.appendingPathComponent(id, isDirectory: true)
    }

    /// New proposal id from a timestamp: sortable, unique per second, safe in
    /// branch names and paths.
    static func makeID(at date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return f.string(from: date)
    }

    /// Missing or corrupt file → a fresh empty store.
    static func load() -> UpdatesStore {
        guard let data = try? Data(contentsOf: storeURL),
              let store = try? decoder().decode(UpdatesStore.self, from: data) else {
            return UpdatesStore()
        }
        return store
    }

    static func save(_ store: UpdatesStore) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        try enc.encode(store).write(to: storeURL, options: .atomic)
    }

    private static func decoder() -> JSONDecoder {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }
}
