import Foundation

/// Resolves the locations nixmc works with.
///
/// The git repo lives in a user-writable directory (no admin to edit/commit).
/// `/etc/nix-darwin` is the canonical path nix-darwin expects; we point it at
/// the repo with a one-time admin-authorized symlink (see `CanonicalConfig`).
struct Paths {
    static let canonicalConfigDir = "/etc/nix-darwin"

    var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    /// Where the actual flake + git repo lives.
    ///
    /// If the user already has a configuration at `/etc/nix-darwin`, use it
    /// directly (resolving any symlink so git/edits hit the real repo). Only
    /// fall back to an app-managed directory when nothing exists yet.
    var repoDir: URL {
        if let custom = Paths.customRepoDir { return custom }
        let canonical = URL(fileURLWithPath: Paths.canonicalConfigDir)
        if FileManager.default.fileExists(atPath: canonical.appending(path: "flake.nix").path) {
            return canonical.resolvingSymlinksInPath()
        }
        return home.appending(path: ".config/nixmc/darwin", directoryHint: .isDirectory)
    }

    /// The user-chosen repo location from Settings, or nil for the automatic
    /// resolution above. Read straight from UserDefaults (not AppSettings) so
    /// off-main-actor callers resolve the same path, and only honored when the
    /// directory still verifies — a repo moved or deleted since it was chosen
    /// must fall back rather than point git at a broken path.
    static var customRepoDir: URL? {
        let raw = UserDefaults.standard.string(forKey: "configRepoPath") ?? ""
        guard let url = normalizedRepoURL(raw),
              verifyRepoOverride(raw) == nil else { return nil }
        return url
    }

    /// The flake directory builds and evaluations target: the user-chosen repo
    /// when one is set (and still valid), else the canonical path.
    static var buildFlakeDir: String {
        customRepoDir?.path ?? canonicalConfigDir
    }

    /// Expand `~` and trim; nil for an empty (= automatic) entry.
    static func normalizedRepoURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath,
                   isDirectory: true).standardizedFileURL
    }

    /// Check a user-supplied repo path: it must be an existing directory that
    /// contains `flake.nix` and is inside a git work tree. Returns nil when
    /// usable, else a human-readable problem for the Settings UI.
    static func verifyRepoOverride(_ raw: String) -> String? {
        guard let url = normalizedRepoURL(raw) else { return nil }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
              isDir.boolValue else {
            return "No folder at \(url.path)."
        }
        guard FileManager.default.fileExists(atPath: url.appending(path: "flake.nix").path) else {
            return "The folder has no flake.nix — it is not a nix-darwin configuration."
        }
        guard let r = try? Shell.run("/usr/bin/git", ["rev-parse", "--is-inside-work-tree"], cwd: url),
              r.ok, r.trimmedOut == "true" else {
            return "The folder is not a git repository."
        }
        return nil
    }

    /// True when a configuration already lives at the canonical path.
    var hasCanonicalConfig: Bool {
        FileManager.default.fileExists(
            atPath: URL(fileURLWithPath: Paths.canonicalConfigDir).appending(path: "flake.nix").path)
    }

    var homebrewData: URL {
        repoDir.appending(path: ".nixmc/homebrew/data.json")
    }

    /// The short host name used to build the `#<host>` flake attribute.
    static func hostName() -> String {
        if let r = try? Shell.run("/usr/sbin/scutil", ["--get", "LocalHostName"]),
           r.ok, !r.trimmedOut.isEmpty {
            return r.trimmedOut
        }
        if let r = try? Shell.run("/bin/hostname", ["-s"]), r.ok, !r.trimmedOut.isEmpty {
            return r.trimmedOut
        }
        return "mac"
    }

    static func userName() -> String { NSUserName() }

    /// Resolve the `darwinConfigurations.<name>` attribute to build/switch.
    ///
    /// Queries the flake for its actual attribute names and prefers one that
    /// matches this host; otherwise takes the only/first entry. Falls back to
    /// the host name when the flake can't be evaluated.
    static func flakeConfigName(fallback: String) -> String {
        let ref = "\(buildFlakeDir)#darwinConfigurations"
        guard let r = try? Shell.login(
                "nix eval '\(ref)' --apply builtins.attrNames --json 2>/dev/null"),
              r.ok,
              let data = r.trimmedOut.data(using: .utf8),
              let names = try? JSONDecoder().decode([String].self, from: data),
              !names.isEmpty
        else { return fallback }

        if names.contains(fallback) { return fallback }
        return names[0]
    }
}
