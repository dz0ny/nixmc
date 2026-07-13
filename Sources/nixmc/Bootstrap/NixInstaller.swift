import Foundation

/// Detects whether Nix is installed. NixMC deliberately does not download or
/// run a system installer; the user installs Nix through their chosen installer.
enum NixInstaller {
    static var isInstalled: Bool {
        // Present if the `nix` binary resolves or the default profile exists.
        if Shell.which("nix") != nil { return true }
        return FileManager.default.fileExists(atPath: "/nix/var/nix/profiles/default")
    }
}
