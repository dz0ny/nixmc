---
id: travel-profile
title: Travel profile
section: For Laptop Nomads
symbol: airplane
summary: Travel profile configuration recipe.
featured: false
mcp-verified: 2026-07-13
mcp-query: darwin options networking.applicationFirewall / services.tailscale / loginwindow
---

Create a travel laptop profile: enable firewall stealth mode, Tailscale, SSH aliases, stricter sleep settings, and a quick status command for network and battery health.

## Guide

nix-darwin has first-class options for the security-sensitive parts of a travel
profile: the macOS application firewall (`networking.applicationFirewall.*`) and
the Tailscale daemon (`services.tailscale.*`). Stricter sleep is a
`system.defaults.loginwindow` key.

Ask the agent to add this to the darwin configuration:

```nix
{
  # macOS application firewall, hardened for untrusted networks.
  networking.applicationFirewall = {
    enable = true;
    enableStealthMode = true;   # do not respond to probes / pings
    blockAllIncoming = true;    # drop all unsolicited inbound
    allowSigned = true;         # still let built-in Apple services work
    allowSignedApp = true;      # ...and downloaded signed apps
  };

  # Tailscale for a private path back to home/work resources.
  services.tailscale.enable = true;

  # Sleep aggressively on the road so a lost/stolen laptop locks fast.
  system.defaults.loginwindow.SleepDisabled = false;
  system.defaults.screensaver.askForPassword = true;
  system.defaults.screensaver.askForPasswordDelay = 0; # require password immediately
}
```

Every option above is a real nix-darwin option (MCP-verified against
`source: darwin`): `networking.applicationFirewall.{enable,enableStealthMode,
blockAllIncoming,allowSigned,allowSignedApp}`, `services.tailscale.enable`, and
the `system.defaults.loginwindow` / `system.defaults.screensaver` keys.

For the non-declarative pieces:

- **SSH aliases** belong in Home Manager (`programs.ssh.matchBlocks`) or a plain
  `~/.ssh/config` managed via `home.file`, not in the darwin `system.defaults`.
- **A "quick status" command** for network + battery is a small wrapper script
  around Apple built-ins (`pmset -g batt`, `ifconfig`, `tailscale status`). Add it
  to `home.packages` with `pkgs.writeShellScriptBin`, e.g.:

  ```nix
  home.packages = [
    (pkgs.writeShellScriptBin "travel-status" ''
      echo "== battery =="; /usr/bin/pmset -g batt
      echo "== network =="; ipconfig getsummary en0 2>/dev/null | head -5
      echo "== tailscale =="; tailscale status 2>/dev/null || echo "not connected"
    '')
  ];
  ```

Run `darwin-rebuild switch` to apply. Enabling stealth mode / block-all-incoming
will affect inbound connections immediately — expect AirDrop and local sharing to
stop working until you relax the profile.
