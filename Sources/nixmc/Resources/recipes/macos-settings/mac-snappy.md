---
mcp-verified: 2026-07-13
mcp-query: "darwin: options system.defaults.NSGlobalDomain"
id: mac-snappy
title: Snappy UI
section: macOS Settings
symbol: bolt
summary: Snappy UI configuration recipe.
featured: false
---

Make the UI snappy: fast key repeat with a short initial delay, disable press-and-hold for accents, and reduce window/Finder animations.

```nix
system.defaults.NSGlobalDomain = {
  InitialKeyRepeat = 15;
  KeyRepeat = 2;
  ApplePressAndHoldEnabled = false;
};

system.defaults.dock.expose-animation-duration = 0.1;
```

## Guide

The keyboard repeats quickly with a short delay, and macOS keeps key accents on
the standard modifier-based path instead of waiting on press-and-hold. Finder
and window animations are reduced so routine navigation feels more immediate.
