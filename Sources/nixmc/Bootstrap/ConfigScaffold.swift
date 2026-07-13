import Foundation

/// Creates a new nix-darwin config from the embedded template and commits it.
enum ConfigScaffold {
    static func exists(repoDir: URL) -> Bool {
        FileManager.default.fileExists(atPath: repoDir.appending(path: "flake.nix").path)
    }

    /// Materialize the template (with placeholder substitution) and `git init`.
    static func create(repoDir: URL) throws {
        let fm = FileManager.default
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

    /// e.g. "aarch64-darwin" / "x86_64-darwin".
    private static func systemDoubleName() -> String {
        #if arch(arm64)
        return "aarch64-darwin"
        #else
        return "x86_64-darwin"
        #endif
    }
}
