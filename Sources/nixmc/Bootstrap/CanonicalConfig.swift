import Foundation

/// Maintains the `/etc/nix-darwin` symlink → repo dir, mirroring nixmc's Rust
/// `ensure_canonical_config_link`. Cheap pre-checks first so the admin prompt
/// appears only on first setup, never on subsequent applies.
enum CanonicalConfig {
    static let link = Paths.canonicalConfigDir

    static func ensureLink(repoDir: URL) throws {
        let fm = FileManager.default
        let target = repoDir.path

        // Already a symlink pointing at the repo? Nothing to do, no prompt.
        if let dest = try? fm.destinationOfSymbolicLink(atPath: link),
           resolve(dest) == resolve(target) {
            return
        }

        // A real (non-symlink) directory already occupying the path.
        if fm.fileExists(atPath: link), !isSymlink(link) {
            let entries = (try? fm.contentsOfDirectory(atPath: link)) ?? []
            let meaningful = entries.filter { $0 != ".DS_Store" }
            if !meaningful.isEmpty, resolve(link) != resolve(target) {
                throw NixmcError.command(
                    "\(link) already contains a configuration. Move or remove it before using a different directory.")
            }
        }

        // Escalate once to (re)create the symlink.
        let script = """
        set -e
        TARGET='\(target)'
        LINK='\(link)'
        if [ -L "$LINK" ] && [ "$(readlink "$LINK")" = "$TARGET" ]; then exit 0; fi
        if [ -e "$LINK" ] && [ ! -L "$LINK" ]; then rm -rf "$LINK"; fi
        ln -sfn "$TARGET" "$LINK"
        """
        try AdminShell.run(script)
    }

    private static func isSymlink(_ path: String) -> Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: path)) != nil
    }

    private static func resolve(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }
}
