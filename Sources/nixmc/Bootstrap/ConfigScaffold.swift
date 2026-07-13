import Foundation

/// Creates a new nix-darwin config from the embedded template and commits it.
enum ConfigScaffold {
    enum Error: LocalizedError {
        case directoryIsNotEmpty(URL)

        var errorDescription: String? {
            switch self {
            case .directoryIsNotEmpty(let directory):
                return "\(directory.path) is not empty. NixMC will not overwrite an existing configuration."
            }
        }
    }

    static func exists(repoDir: URL) -> Bool {
        FileManager.default.fileExists(atPath: repoDir.appending(path: "flake.nix").path)
    }

    /// A starter configuration is only safe to create in an empty location.
    static func canCreate(repoDir: URL) -> Bool {
        let fm = FileManager.default
        guard !exists(repoDir: repoDir) else { return false }
        guard fm.fileExists(atPath: repoDir.path) else { return true }
        guard let contents = try? fm.contentsOfDirectory(atPath: repoDir.path) else { return false }
        return contents.allSatisfy { $0 == ".DS_Store" }
    }

    /// Materialize the template (with placeholder substitution) and `git init`.
    static func create(repoDir: URL) throws {
        let fm = FileManager.default
        guard canCreate(repoDir: repoDir) else {
            throw Error.directoryIsNotEmpty(repoDir)
        }
        let subs = [
            "@HOSTNAME@": Paths.hostName(),
            "@USERNAME@": Paths.userName(),
            "@SYSTEM@": systemDoubleName(),
        ]

        for (rel, raw) in ConfigTemplate.files {
            var content = raw
            for (k, v) in subs { content = content.replacingOccurrences(of: k, with: v) }
            let dest = repoDir.appending(path: rel)
            try fm.createDirectory(at: dest.deletingLastPathComponent(),
                                   withIntermediateDirectories: true)
            try content.write(to: dest, atomically: true, encoding: .utf8)
        }

        if !fm.fileExists(atPath: repoDir.appending(path: ".git").path) {
            _ = try Shell.run("/usr/bin/git", ["init", "-q"], cwd: repoDir)
        }
        _ = try Shell.run("/usr/bin/git", ["add", "-A"], cwd: repoDir)
        _ = try Shell.run("/usr/bin/git",
                          ["commit", "-q", "-m", "chore: initial nix-darwin configuration"],
                          cwd: repoDir)
    }

    /// Move an existing configuration aside, then materialize a fresh template.
    /// The backup stays beside the new repository so it can be inspected or
    /// restored manually if needed.
    @discardableResult
    static func replaceWithTemplate(repoDir: URL) throws -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: repoDir.path) else {
            try create(repoDir: repoDir)
            return repoDir
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: Date())
        let backup = repoDir.deletingLastPathComponent()
            .appending(path: "\(repoDir.lastPathComponent)-backup-\(stamp)")

        try fm.moveItem(at: repoDir, to: backup)
        do {
            try create(repoDir: repoDir)
        } catch {
            // Do not leave the user without their working configuration if
            // creating the replacement fails after the archive succeeded.
            try? fm.moveItem(at: backup, to: repoDir)
            throw error
        }
        return backup
    }

    /// e.g. "aarch64-darwin" / "x86_64-darwin".
    private static func systemDoubleName() -> String {
        #if arch(arm64)
        return "aarch64-darwin"
        #else
        return "x86_64-darwin"
        #endif
    }
}
