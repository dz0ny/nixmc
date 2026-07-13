---
mcp-verified: 2026-07-13
mcp-query: "darwin: options system.defaults.screencapture"
id: mac-screenshots
title: Screenshot defaults
section: macOS Settings
symbol: camera.viewfinder
summary: Screenshot defaults configuration recipe.
featured: false
---

Send screenshots to ~/Pictures/Screenshots as PNG without the drop shadow, and disable the floating thumbnail.

```nix
system.defaults.screencapture = {
  location = "/Users/USER/Pictures/Screenshots";
  type = "png";
  disable-shadow = true;
  show-thumbnail = false;
};
```

Replace `USER` with the primary account name.
