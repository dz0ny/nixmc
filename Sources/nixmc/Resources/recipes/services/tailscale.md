---
id: tailscale
title: Run Tailscale at boot
section: Services
symbol: network
summary: Start the Tailscale daemon declaratively so the Mac can rejoin its tailnet after reboot.
featured: false
source: https://github.com/staticWagomU/dotfiles
mcp-verified: 2026-07-13
mcp-query: darwin options services.tailscale
---

Enable the nix-darwin service in the system module. Do not put an auth key or
other secret directly in the flake; authenticate interactively after the first
successful apply, or use the user's existing secret-management setup.

```nix
services.tailscale.enable = true;
```

Verify whether the user also wants the GUI cask. The service and the GUI are
separate choices.
