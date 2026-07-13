---
id: tidy-dock
title: Keep the Dock tidy
section: macOS Settings
symbol: dock.rectangle
summary: Enable fast autohide, disable recents, and keep Spaces predictable.
featured: false
source: https://github.com/nix-darwin/nix-darwin/blob/master/modules/system/defaults/dock.nix
mcp-verified: 2026-07-13
mcp-query: darwin options system.defaults.dock
---

Add this to `system.defaults.dock` in the nix-darwin module, merging it with
existing Dock settings.

```nix
system.defaults.dock = {
  autohide = true;
  autohide-delay = 0.0;
  show-recents = false;
  minimize-to-application = true;
  mru-spaces = false;
  tilesize = 44;
};
```

Do not remove user-pinned Dock applications unless the request explicitly says
to manage the Dock contents.
