import Foundation

/// Accumulates streamed bytes and yields complete newline-terminated lines.
/// A reference type so the `Process` readability closure can mutate it safely.
final class LineBuffer {
    private var data = Data()

    func append(_ chunk: Data) -> [String] {
        data.append(chunk)
        var lines: [String] = []
        while let nl = data.firstIndex(of: 0x0A) {
            let line = data.subdata(in: data.startIndex..<nl)
            data.removeSubrange(data.startIndex...nl)
            lines.append(String(decoding: line, as: UTF8.self))
        }
        return lines
    }

    func flush() -> String? {
        guard !data.isEmpty else { return nil }
        let s = String(decoding: data, as: UTF8.self)
        data.removeAll()
        return s
    }
}

/// Result of a finished command.
struct CommandResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
    var ok: Bool { exitCode == 0 }
    var trimmedOut: String { stdout.trimmingCharacters(in: .whitespacesAndNewlines) }
}

enum NixmcError: LocalizedError {
    case admin(String)
    case adminCanceled
    case command(String)

    var errorDescription: String? {
        switch self {
        case .admin(let d): return "Administrator command failed: \(d)"
        case .adminCanceled: return "Administrator approval is required to continue."
        case .command(let d): return d
        }
    }
}

/// Thin wrapper around `Process`.
///
/// A menu-bar app launched from Finder inherits a minimal PATH that omits
/// `/nix/var/nix/profiles/...`, Homebrew, and user tools. So anything that needs
/// to reach `nix`, `darwin-rebuild`, `git`, or an agent CLI runs through a login
/// shell (`zsh -lc`) to pick up the user's real PATH.
enum Shell {
    /// Environment for children launched from the app. Finder/LaunchServices
    /// commonly provide only the macOS system PATH; a login shell is useful for
    /// user tools, but non-interactive `zsh -lc` does not read `.zshrc`. Add
    /// the standard Nix profile locations explicitly so NixMC can find Nix
    /// even when the user's shell setup lives solely in `.zshrc`.
    private static func childEnvironment(overriding overrides: [String: String]?) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        if let overrides {
            environment.merge(overrides) { _, replacement in replacement }
        }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let nixBinDirectories = [
            "/nix/var/nix/profiles/default/bin",
            "/run/current-system/sw/bin",
            "\(home)/.nix-profile/bin",
            "/etc/profiles/per-user/\(NSUserName())/bin",
        ].filter {
            FileManager.default.fileExists(atPath: $0, isDirectory: nil)
        }
        let currentPath = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        let pathEntries = nixBinDirectories + currentPath.split(separator: ":").map(String.init)
        environment["PATH"] = Array(NSOrderedSet(array: pathEntries)).compactMap { $0 as? String }
            .joined(separator: ":")
        return environment
    }

    /// Run an executable directly to completion, capturing output.
    static func run(_ launchPath: String, _ args: [String],
                    cwd: URL? = nil, env: [String: String]? = nil) throws -> CommandResult {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args
        if let cwd { p.currentDirectoryURL = cwd }
        p.environment = childEnvironment(overriding: env)
        p.standardInput = FileHandle.nullDevice
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        try p.run()
        let o = out.fileHandleForReading.readDataToEndOfFile()
        let e = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return CommandResult(exitCode: p.terminationStatus,
                             stdout: String(decoding: o, as: UTF8.self),
                             stderr: String(decoding: e, as: UTF8.self))
    }

    /// Run a shell script through an interactive login shell (real user PATH).
    static func login(_ script: String, cwd: URL? = nil) throws -> CommandResult {
        try run("/bin/zsh", ["-lc", script], cwd: cwd)
    }

    /// Resolve a binary on the login-shell PATH.
    static func which(_ name: String) -> String? {
        guard let r = try? login("command -v \(name)"), r.ok else { return nil }
        let path = r.trimmedOut
        return path.isEmpty ? nil : path
    }

    /// Stream a login-shell command line by line; returns the exit code.
    /// `input`, when given, is piped to the command's stdin (then closed).
    /// `onSpawn` receives the child PID once launched (for cancellation).
    @discardableResult
    static func streamLogin(_ script: String, cwd: URL? = nil, input: String? = nil,
                            onSpawn: ((Int32) -> Void)? = nil,
                            onLine: @escaping (String) -> Void) async -> Int32 {
        await stream("/bin/zsh", ["-lc", script], cwd: cwd, input: input,
                     onSpawn: onSpawn, onLine: onLine)
    }

    @discardableResult
    static func stream(_ launchPath: String, _ args: [String], cwd: URL? = nil,
                       input: String? = nil,
                       onSpawn: ((Int32) -> Void)? = nil,
                       onLine: @escaping (String) -> Void) async -> Int32 {
        await withCheckedContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: launchPath)
            p.arguments = args
            if let cwd { p.currentDirectoryURL = cwd }
            p.environment = childEnvironment(overriding: nil)
            // A GUI app inherits an open, TTY-less stdin. Agent CLIs (e.g. claude)
            // detect the non-TTY and block reading stdin instead of acting on the
            // prompt. Feed them the requested input (or /dev/null) so they see EOF.
            if let input {
                let inPipe = Pipe()
                p.standardInput = inPipe
                let handle = inPipe.fileHandleForWriting
                DispatchQueue.global().async {
                    handle.write(Data(input.utf8))
                    try? handle.close()
                }
            } else {
                p.standardInput = FileHandle.nullDevice
            }
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = pipe
            let handle = pipe.fileHandleForReading
            let buffer = LineBuffer()
            handle.readabilityHandler = { h in
                let d = h.availableData
                guard !d.isEmpty else { return }
                for line in buffer.append(d) { onLine(line) }
            }
            p.terminationHandler = { proc in
                handle.readabilityHandler = nil
                if let last = buffer.flush() { onLine(last) }
                cont.resume(returning: proc.terminationStatus)
            }
            do {
                try p.run()
                onSpawn?(p.processIdentifier)
            } catch {
                handle.readabilityHandler = nil
                onLine("failed to launch \(launchPath): \(error.localizedDescription)")
                cont.resume(returning: -1)
            }
        }
    }

    /// Interrupt a process and all its descendants (nix build spawns children).
    /// Sends SIGINT — nix and darwin-rebuild unwind cleanly on it, like Ctrl-C.
    static func interruptTree(_ pid: Int32) {
        var pids: [Int32] = []
        func collect(_ p: Int32) {
            pids.append(p)
            guard let r = try? run("/usr/bin/pgrep", ["-P", "\(p)"]), r.ok else { return }
            for line in r.stdout.split(whereSeparator: \.isNewline) {
                if let child = Int32(line.trimmingCharacters(in: .whitespaces)) { collect(child) }
            }
        }
        collect(pid)
        // Leaves first so parents don't respawn work as children die.
        for p in pids.reversed() { kill(p, SIGINT) }
    }
}
