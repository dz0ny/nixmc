---
id: window-workflow
title: Window workflow
section: For Designers
symbol: rectangle.3.group
summary: Window workflow configuration recipe.
featured: false
mcp-verified: 2026-07-13
mcp-query: darwin options services.yabai / system.defaults.dock / system.defaults.WindowManager
---

Set up a design-friendly window workflow with AeroSpace or yabai, Raycast, Rectangle, clean hotkeys, and sensible Dock and Stage Manager defaults.

Raycast, Rectangle, and AeroSpace ship as Homebrew casks via the nixmc JSON — add them to `.nixmc/homebrew/data.json`:

```json
{
  "casks": ["raycast", "rectangle", "nikitabobko/tap/aerospace"]
}
```

yabai is a nix-darwin service (leave `enableScriptingAddition` off unless you have disabled SIP). Put the tiling service plus the Dock and Stage Manager defaults in the nix-darwin module. Preserve existing attributes:

```nix
services.yabai = {
  enable = true;
  config = {
    layout = "bsp";
    window_gap = 8;
  };
};

system.defaults.dock = {
  autohide = true;
  mru-spaces = false;
  minimize-to-application = true;
};

system.defaults.WindowManager = {
  GloballyEnabled = true;
  EnableTilingByEdgeDrag = true;
  AutoHide = true;
};
```
