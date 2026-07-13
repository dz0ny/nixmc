---
id: homebrew-apps
title: Add desktop apps with Homebrew
section: Packages
symbol: macwindow
summary: Add GUI apps as declarative Homebrew casks in nixmc's JSON data file.
featured: true
source: https://github.com/nix-darwin/nix-darwin
mcp-verified: 2026-07-13
mcp-query: darwin homebrew.casks module (cask slugs not indexed by nixos MCP)
---

Edit `.nixmc/homebrew/data.json`, not a Nix module. Add only the requested
casks and preserve the existing activation policy.

```json
{
  "casks": [
    "brave-browser",
    "claude",
    "codex",
    "ghostty",
    "localsend",
    "pareto-security",
    "proton-pass",
    "raycast",
    "rectangle",
    "rustdesk",
    "signal",
    "slack",
    "spotify",
    "tailscale-app",
    "teamviewer",
    "visual-studio-code",
    "zed"
  ],
  "onActivation": { "autoUpdate": true, "upgrade": true, "cleanup": "none" }
}
```

Use Homebrew casks for GUI apps; keep developer CLIs in `home.nix` where
possible. Cask slugs are exact Homebrew identifiers: preserve existing entries
unless the requested app itself changes. `cleanup: "none"` makes this additive:
NixMC installs and updates the listed apps but never uninstalls or zaps apps
that are not listed.
