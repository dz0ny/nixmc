import Foundation

/// Best-effort formatting of the config's `.nix` files after the agent edits them.
///
/// We don't require a formatter to be installed: a single login-shell snippet
/// picks the first available tool (treefmt → nixfmt → alejandra → nixpkgs-fmt →
/// `nix fmt` if the flake exposes a `formatter` output) and no-ops otherwise, so
/// the step is harmless when the toolchain has none. `data.json` is JSON, not Nix,
/// so it is intentionally untouched.
enum NixFormat {
    private static let script = """
    if command -v treefmt >/dev/null 2>&1; then treefmt; \
    elif command -v nixfmt >/dev/null 2>&1; then \
         find . -name '*.nix' -not -path './.git/*' -print0 | xargs -0 nixfmt; \
    elif command -v alejandra >/dev/null 2>&1; then alejandra -q .; \
    elif command -v nixpkgs-fmt >/dev/null 2>&1; then nixpkgs-fmt .; \
    elif nix eval .#formatter --apply 'builtins.attrNames' >/dev/null 2>&1; then nix fmt; \
    else echo 'no nix formatter found; skipping'; fi
    """

    static func run(repoDir: URL, onLine: @escaping (String) -> Void) async {
        _ = await Shell.streamLogin(script, cwd: repoDir, onLine: onLine)
    }

    /// Format one source file from the in-app editor. Prefer formatters that
    /// accept a path; treefmt/nix fmt are repository-wide and deliberately
    /// remain reserved for the build/apply pipeline.
    static func format(file: URL, repoDir: URL, onLine: @escaping (String) -> Void) async -> Bool {
        let path = shellQuote(file.path)
        let script = """
        if command -v nixfmt >/dev/null 2>&1; then nixfmt \(path); \\
        elif command -v alejandra >/dev/null 2>&1; then alejandra -q \(path); \\
        elif command -v nixpkgs-fmt >/dev/null 2>&1; then nixpkgs-fmt \(path); \\
        else echo 'no file-level Nix formatter found (install nixfmt, alejandra, or nixpkgs-fmt)'; exit 1; fi
        """
        return await Shell.streamLogin(script, cwd: repoDir, onLine: onLine) == 0
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
