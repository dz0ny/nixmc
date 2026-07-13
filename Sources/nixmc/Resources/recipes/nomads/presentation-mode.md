---
id: presentation-mode
title: Presentation mode
section: For Laptop Nomads
symbol: play.rectangle
summary: Presentation mode configuration recipe.
featured: false
mcp-verified: 2026-07-13
mcp-query: darwin options screensaver / loginwindow / dock / finder / launchd.daemons
---

Add a presentation mode profile that keeps the display awake on AC power, disables notification-prone startup apps, and adds a one-command toggle.

## Guide

The declarative pieces (no screensaver, no password prompt, hidden desktop icons,
auto-hidden dock) are `system.defaults`. Keeping the display awake is a `pmset`
concern, which nix-darwin exposes through a `launchd` daemon rather than a
`system.defaults` key.

Ask the agent to add this to the darwin configuration:

```nix
{
  # Screen never asks for a password when it wakes (kiosk / presenting).
  system.defaults.screensaver.askForPassword = false;

  # Keep the machine awake while plugged in and never auto-shut-off the display.
  system.defaults.loginwindow.SleepDisabled = true;

  # Calm, distraction-free desktop.
  system.defaults.dock.autohide = true;
  system.defaults.finder.CreateDesktop = false; # hide all desktop icons

  # Force "presentation" power behaviour on AC: display + system stay awake.
  # `pmset -c` targets charger/AC power; runs once at activation.
  launchd.daemons.presentation-power = {
    command = "/usr/bin/pmset -c displaysleep 0 sleep 0 disksleep 0";
    serviceConfig = {
      RunAtLoad = true;
      KeepAlive = false;
    };
  };
}
```

All four `system.defaults.*` keys and `launchd.daemons.<name>.command` /
`serviceConfig` are real nix-darwin options (MCP-verified against `source: darwin`).

Notes:

- `pmset`, `caffeinate`, and `osascript` are Apple built-ins — do not add them to
  `home.packages`; call them by absolute path (`/usr/bin/pmset`) from the daemon.
- To make presentation mode a *toggle* rather than always-on, remove this block
  when you are done presenting and rebuild — the values revert to their macOS
  defaults. A live on/off switch without a rebuild would be a `caffeinate` wrapper
  script in `home.packages`, which is out of scope for the declarative config.
- Run `darwin-rebuild switch` to apply; the settings and daemon take effect at
  activation.
