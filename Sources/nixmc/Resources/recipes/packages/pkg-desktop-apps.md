---
mcp-verified: manual
mcp-query: not-applicable
id: pkg-desktop-apps
title: Install everyday desktop apps
section: Packages
symbol: macwindow
summary: Install messaging, productivity, coding, terminal, and media apps as Homebrew casks.
featured: false
---

Install my everyday desktop apps as Homebrew casks. Use these exact Homebrew
cask names in `.nixmc/homebrew/data.json`:

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

Keep `cleanup` set to `"none"`: applying this recipe installs or updates the
listed apps, but does not uninstall or zap any existing Homebrew cask.
