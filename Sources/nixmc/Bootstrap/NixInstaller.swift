import Foundation

/// Detects Nix and installs it with Determinate's signed macOS package.
enum NixInstaller {
    private static let packageURL = "https://install.determinate.systems/determinate-pkg/stable/Universal"
    private static let developerTeamID = "X3JQ4VPJZ6"
    static var isInstalled: Bool {
        // Present if the `nix` binary resolves or the default profile exists.
        if Shell.which("nix") != nil { return true }
        return FileManager.default.fileExists(atPath: "/nix/var/nix/profiles/default")
    }

    /// Downloads Determinate's universal macOS package, verifies its signing
    /// team, then installs it through macOS Installer with administrator approval.
    static func install(onLine: @escaping (String) -> Void) async -> Bool {
        let script = """
        set -eu
        scratch=$(/usr/bin/mktemp -d /private/tmp/nixmc-determinate.XXXXXX)
        trap '/bin/rm -rf "$scratch"' EXIT
        package="$scratch/Determinate.pkg"

        echo "Downloading Determinate Nix package…"
        /usr/bin/curl --proto '=https' --tlsv1.2 -sSf -L "\(packageURL)" -o "$package"

        actualTeamID=$(/usr/sbin/spctl -a -vv -t install "$package" 2>&1 \
          | /usr/bin/awk -F '(' '/origin=/ {print $2}' | /usr/bin/tr -d '()')
        if [ "$actualTeamID" != "\(developerTeamID)" ]; then
          echo "Package signature verification failed (expected \(developerTeamID), got ${actualTeamID:-unknown})." >&2
          exit 1
        fi

        echo "Installing verified Determinate Nix package…"
        /usr/sbin/installer -verboseR -pkg "$package" -target /
        """
        // Run the privileged installer through one native macOS authorization
        // prompt. The package is downloaded and signature-checked in this same
        // root-owned temporary directory before installation.
        let escaped = script.replacingOccurrences(of: "\\", with: "\\\\")
                            .replacingOccurrences(of: "\"", with: "\\\"")
        let osa = "do shell script \"\(escaped)\" with administrator privileges"
        return await Shell.stream("/usr/bin/osascript", ["-e", osa], onLine: onLine) == 0
    }
}
