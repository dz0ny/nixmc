import Foundation

/// One-shot privilege escalation via AppleScript, mirroring nixmc's Rust
/// `run_privileged_shell`. No installed helper/XPC — macOS shows its native
/// admin auth dialog. Reserve this for genuinely privileged steps (Determinate
/// install, `/etc/nix-darwin` setup, `darwin-rebuild switch`).
enum AdminShell {
    static func run(_ script: String) throws {
        let esc = script
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let osa = "do shell script \"\(esc)\" with administrator privileges"
        let r = try Shell.run("/usr/bin/osascript", ["-e", osa])
        guard r.ok else {
            let detail = r.stderr.isEmpty ? r.stdout : r.stderr
            if detail.lowercased().contains("user canceled") {
                throw NixmcError.adminCanceled
            }
            throw NixmcError.admin(detail.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
