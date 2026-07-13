---
mcp-verified: 2026-07-13
mcp-query: "darwin: options system.defaults.finder"
id: mac-finder
title: Finder power user
section: macOS Settings
symbol: folder
summary: Finder power user configuration recipe.
featured: false
---

Finder power-user defaults: show all file extensions, hidden files, the path bar and status bar, default to list view, and search the current folder.

```nix
system.defaults.finder = {
  AppleShowAllExtensions = true;
  AppleShowAllFiles = true;
  ShowPathbar = true;
  ShowStatusBar = true;
  FXPreferredViewStyle = "Nlsv";
  FXDefaultSearchScope = "SCcf";
};
```
