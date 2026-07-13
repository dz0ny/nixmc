---
id: mac-trackpad
title: Trackpad & keyboard
section: macOS Settings
symbol: hand.point.up.left
summary: Trackpad & keyboard configuration recipe.
featured: false
source: https://github.com/nix-darwin/nix-darwin/blob/master/modules/system/defaults/trackpad.nix
mcp-verified: 2026-07-13
mcp-query: darwin options system.defaults.trackpad
---

Enable tap-to-click, full keyboard access for controls, and turn off “natural” scrolling.

Add these to the nix-darwin module. Tap-to-click lives under
`system.defaults.trackpad`; full keyboard access and the scroll direction live
under `system.defaults.NSGlobalDomain`.

```nix
system.defaults.trackpad.Clicking = true;
system.defaults.NSGlobalDomain = {
  "com.apple.mouse.tapBehavior" = 1;        # tap to click
  "com.apple.swipescrolldirection" = false; # disable "natural" scrolling
  AppleKeyboardUIMode = 3;                   # full keyboard access for all controls
};
```

Note: three-finger drag is not exposed as a dedicated nix-darwin option — it lives
in the `com.apple.AppleMultitouchTrackpad` accessibility domain, which
`system.defaults` does not cover, so it is left out here. `trackpad.Clicking` and
`NSGlobalDomain."com.apple.mouse.tapBehavior" = 1` together enable tap-to-click.
</content>
</invoke>
