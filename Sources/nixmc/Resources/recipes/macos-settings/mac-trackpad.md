---
mcp-verified: 2026-07-13
mcp-query: "darwin: options system.defaults.NSGlobalDomain"
id: mac-trackpad
title: Trackpad & keyboard
section: macOS Settings
symbol: hand.point.up.left
summary: Trackpad & keyboard configuration recipe.
featured: false
---

Enable tap-to-click, three-finger drag, full keyboard access for controls, and turn off “natural” scrolling.

```nix
system.defaults.trackpad.Clicking = true;
system.defaults.NSGlobalDomain.AppleKeyboardUIMode = 3;
```

Three-finger drag and the natural-scroll direction remain Accessibility/manual
settings because they are not indexed as dedicated nix-darwin options.
