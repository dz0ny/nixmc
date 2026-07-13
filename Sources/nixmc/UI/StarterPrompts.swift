import Foundation

/// A focused configuration area in the sidebar. The actual recipes are
/// Markdown resources in `Resources/recipes/<section>/<title>.md`.
struct StarterArea: Identifiable, Hashable {
    let id: String
    let symbol: String
    let summary: String
}

/// Sidebar metadata shared with the generated configuration guide. Keeping this
/// small and static lets recipes evolve independently without changing Swift.
enum StarterPrompts {
    static let areas: [StarterArea] = [
        StarterArea(id: "My Team", symbol: "person.3",
                    summary: "Hand-curated recipes shared from your team's repository."),
        StarterArea(id: "Packages", symbol: "shippingbox",
                    summary: "Add tools and apps to your config — CLI packages and Homebrew casks."),
        StarterArea(id: "Fonts", symbol: "textformat",
                    summary: "Add fonts to `fonts.packages` so they are available system-wide."),
        StarterArea(id: "macOS Settings", symbol: "slider.horizontal.3",
                    summary: "Set macOS system defaults declaratively via `system.defaults`."),
        StarterArea(id: "Services", symbol: "gearshape.2",
                    summary: "Run background services and launchd agents with nix-darwin."),
        StarterArea(id: "Shell & Environment", symbol: "curlybraces",
                    summary: "Configure shells, developer environments, and interactive tooling."),
        StarterArea(id: "AI Agents", symbol: "sparkles",
                    summary: "Manage Codex, Claude Code, and OpenCode declaratively with Home Manager."),
        StarterArea(id: "Security & Secrets", symbol: "lock.shield",
                    summary: "Harden sudo, firewall, SSH, and secret handling.")
    ]
}
