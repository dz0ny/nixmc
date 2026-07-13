---
id: finder-power-user
title: Make Finder more useful
section: macOS Settings
symbol: folder
summary: Show extensions and useful bars, default to list view, and search the current folder.
featured: true
source: https://github.com/nix-darwin/nix-darwin/blob/master/modules/system/defaults/finder.nix
mcp-verified: 2026-07-13
mcp-query: darwin options system.defaults.finder
---

Place these settings in the nix-darwin module in `flake.nix`. Preserve any
existing `system.defaults.finder` attributes.

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

Explain that Finder may need to be restarted or reopened before every default is
visible.
