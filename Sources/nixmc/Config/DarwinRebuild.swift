import Foundation

/// Drives `darwin-rebuild build` / `switch` against the canonical flake.
///
/// Under Determinate Nix, `darwin-rebuild` isn't on PATH globally, so we invoke
/// it via `nix run nix-darwin#darwin-rebuild`. Runs through a login shell for the
/// user's PATH; `switch` is escalated (activation writes to system locations).
enum DarwinRebuild {
    static func flakeRef(host: String) -> String {
        "\(Paths.buildFlakeDir)#\(host)"
    }

    private static func rebuildInvocation(_ sub: String, flakeRef: String) -> String {
        // Prefer a real darwin-rebuild if present; else fall back to `nix run`.
        "if command -v darwin-rebuild >/dev/null 2>&1; then "
        + "darwin-rebuild \(sub) --flake \(flakeRef); "
        + "else nix run nix-darwin#darwin-rebuild -- \(sub) --flake \(flakeRef); fi"
    }

    /// Validate the configuration. Returns true on success.
    ///
    /// Runs with cwd = `repoDir` (user-writable, `result` gitignored) so
    /// `darwin-rebuild build`'s `./result` symlink doesn't land in the
    /// Finder-inherited cwd `/`, which is read-only on modern macOS.
    static func build(host: String, onSpawn: ((Int32) -> Void)? = nil,
                      onLine: @escaping (String) -> Void) async -> Bool {
        await Shell.streamLogin(rebuildInvocation("build", flakeRef: flakeRef(host: host)),
                                cwd: Paths().repoDir, onSpawn: onSpawn, onLine: onLine) == 0
    }

    /// Validate an arbitrary flake directory — an update-proposal worktree —
    /// without touching /etc/nix-darwin. Runs with cwd = `flakeDir` so the
    /// `./result` symlink lands there (the caller deletes it after).
    static func build(flakeDir: URL, host: String, onSpawn: ((Int32) -> Void)? = nil,
                      onLine: @escaping (String) -> Void) async -> Bool {
        let ref = shQuote("\(flakeDir.path)#\(host)")
        return await Shell.streamLogin(rebuildInvocation("build", flakeRef: ref),
                                       cwd: flakeDir, onSpawn: onSpawn, onLine: onLine) == 0
    }

    /// Activate the configuration (admin). Returns true on success.
    ///
    /// `darwin-rebuild switch` under sudo re-evaluates the flake as root, and
    /// Nix's git fetcher then refuses the user-owned repo ("repository path …
    /// is not owned by current user"). So we never evaluate as root: resolve the
    /// built system store path as the user (instant — the build step already
    /// cached it), then escalate only to set the system profile and run the
    /// store path's activation script. Root never touches the git repo.
    ///
    /// Privilege escalation mirrors the original nixmc (Rust/Tauri) app's
    /// `run_activate_with_path`: `osascript "with administrator privileges"`
    /// writes a temporary, content-addressed `NOPASSWD` sudoers rule scoped to
    /// this exact activate path, removed via a shell `trap` on exit — no
    /// persistent config. Activation is run via `launchctl asuser <uid> sudo -E
    /// -n` rather than plain `sudo`, because a root process spawned by osascript
    /// lives in the *system* bootstrap domain; nix-darwin's activation script
    /// checks `launchctl managername == "Aqua"` and aborts with a bogus
    /// "updating apps over SSH" error otherwise. `launchctl asuser` re-enters the
    /// user's Aqua session domain before sudo runs.
    ///
    /// Extension over the original: activation drops from root back to the
    /// plain user to run Homebrew, and Homebrew's cask installer issues its own
    /// `sudo` calls as that plain user — `sudo chmod -R a+rX
    /// /Applications/<App>.app` for app bundles, and `sudo /usr/sbin/installer
    /// -pkg <Caskroom>/… -target /` for pkg-based casks (e.g. TeamViewer). That
    /// user has no tty and no ticket, so each dies with "a terminal is required
    /// to read the password". Two more temp NOPASSWD rules, scoped to exactly
    /// those command patterns for the plain user, close the gap the same
    /// self-cleaning way.
    static func switchTo(host: String, onLine: @escaping (String) -> Void) async -> Bool {
        // 1) As the user: materialize the system closure and print its store path.
        var storePath = ""
        let resolve = "nix build --no-link --print-out-paths "
            + shQuote("\(Paths.buildFlakeDir)#darwinConfigurations.\(host).system")
        let code = await Shell.streamLogin(resolve) { line in
            if line.hasPrefix("/nix/store/") { storePath = line.trimmingCharacters(in: .whitespaces) }
            onLine(line)
        }
        guard code == 0, !storePath.isEmpty else {
            onLine("switch failed: couldn't resolve the built system (see above)")
            return false
        }

        // 2) As root (scoped, self-removing NOPASSWD rules): set the system
        // profile and activate.
        let logPath = "/private/tmp/nixmc-activate.log"
        FileManager.default.createFile(atPath: logPath, contents: Data())
        let user = NSUserName()
        let home = ProcessInfo.processInfo.environment["HOME"] ?? "/Users/\(user)"
        let sshSock = ProcessInfo.processInfo.environment["SSH_AUTH_SOCK"] ?? ""
        let path = (try? Shell.login("echo $PATH"))?.trimmedOut ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        // The administrator shell launched by osascript has macOS's minimal
        // PATH. Resolve nix-env before escalating and invoke that exact binary
        // below, rather than assuming the root shell inherited the Nix profile.
        guard let nixEnv = Shell.which("nix-env") else {
            onLine("switch failed: nix-env was not found on the NixMC user's login-shell PATH")
            return false
        }
        let activatePath = "\(storePath)/activate"
        let caskroom = "\(brewPrefix())/Caskroom"

        let script = """
        set -e
        ACTIVATE=\(shQuote(activatePath))
        SYSTEM_PATH=\(shQuote(storePath))
        NIXMC_USER=\(shQuote(user))
        CASKROOM=\(shQuote(caskroom))
        USER_ID=$(id -u "$NIXMC_USER")

        trap 'rm -f /etc/sudoers.d/nixmc-activate-temp /etc/sudoers.d/nixmc-brew-temp /etc/sudoers.d/nixmc-pkg-temp' EXIT

        printf '%s ALL=(ALL) NOPASSWD: %s\\n' "$NIXMC_USER" "$ACTIVATE" \\
            > /etc/sudoers.d/nixmc-activate-temp
        chmod 440 /etc/sudoers.d/nixmc-activate-temp
        visudo -cf /etc/sudoers.d/nixmc-activate-temp >/dev/null

        printf '%s ALL=(ALL) NOPASSWD:SETENV: /bin/chmod -R a+rX /Applications/*\\n' "$NIXMC_USER" \\
            > /etc/sudoers.d/nixmc-brew-temp
        chmod 440 /etc/sudoers.d/nixmc-brew-temp
        visudo -cf /etc/sudoers.d/nixmc-brew-temp >/dev/null

        printf '%s ALL=(ALL) NOPASSWD:SETENV: /usr/sbin/installer -pkg %s/* -target /*\\n' "$NIXMC_USER" "$CASKROOM" \\
            > /etc/sudoers.d/nixmc-pkg-temp
        chmod 440 /etc/sudoers.d/nixmc-pkg-temp
        visudo -cf /etc/sudoers.d/nixmc-pkg-temp >/dev/null

        {
            \(shQuote(nixEnv)) -p /nix/var/nix/profiles/system --set "$SYSTEM_PATH"
            export PATH=\(shQuote(path))
            export HOME=\(shQuote(home))
            export SSH_AUTH_SOCK=\(shQuote(sshSock))
            launchctl asuser "$USER_ID" sudo -E -n "$ACTIVATE"
        } > \(shQuote(logPath)) 2>&1
        """

        let tailer = tailLog(logPath, onLine: onLine)
        defer { tailer.cancel() }
        do {
            // AdminShell.run blocks; hop off the cooperative pool so the tailer runs.
            try await Task.detached { try AdminShell.run(script) }.value
            try? await Task.sleep(nanoseconds: 300_000_000) // let the tailer catch up
            onLine("switch completed")
            return true
        } catch {
            if let output = try? String(contentsOfFile: logPath, encoding: .utf8),
               output.contains("Operation not permitted"),
               output.contains("/Applications/") {
                onLine("Hint: Allow nixmc to manage applications in System Settings > Privacy & Security > App Management, then apply again.")
            }
            onLine("switch failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Poll-tail a log file, emitting complete lines until cancelled (then a
    /// final drain). Poll interval keeps activation output near-live without
    /// holding any FD open across the privileged child.
    private static func tailLog(_ path: String,
                                onLine: @escaping (String) -> Void) -> Task<Void, Never> {
        Task.detached {
            var offset: UInt64 = 0
            let buffer = LineBuffer()
            func drain() {
                guard let fh = FileHandle(forReadingAtPath: path) else { return }
                defer { try? fh.close() }
                try? fh.seek(toOffset: offset)
                guard let d = try? fh.readToEnd(), !d.isEmpty else { return }
                offset += UInt64(d.count)
                for line in buffer.append(d) { onLine(line) }
            }
            while !Task.isCancelled {
                drain()
                try? await Task.sleep(nanoseconds: 400_000_000)
            }
            drain()
            if let rest = buffer.flush() { onLine(rest) }
        }
    }

    /// Homebrew prefix for the sudoers Caskroom pattern: derived from `brew`
    /// on the login-shell PATH (`<prefix>/bin/brew`), else the stock per-arch
    /// location.
    private static func brewPrefix() -> String {
        if let brew = Shell.which("brew") {
            return URL(fileURLWithPath: brew)
                .deletingLastPathComponent()  // bin
                .deletingLastPathComponent()  // prefix
                .path
        }
        #if arch(arm64)
        return "/opt/homebrew"
        #else
        return "/usr/local"
        #endif
    }

    private static func shQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
