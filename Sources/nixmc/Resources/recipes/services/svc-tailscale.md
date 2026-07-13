---
id: svc-tailscale
title: Rejoin Tailscale automatically
section: Services
symbol: network
summary: Start Tailscale at boot so this Mac automatically rejoins its private tailnet.
featured: false
source: https://github.com/nix-darwin/nix-darwin
mcp-verified: 2026-07-13
mcp-query: darwin options services.tailscale
---

Enable the Tailscale service so my Mac joins the tailnet automatically on boot.
nix-darwin ships `services.tailscale.enable`, which installs the client daemon
(`tailscaled`) as a launchd service. Add this to the system module:

```nix
services.tailscale.enable = true;
```

Do not put an auth key or other secret in the flake. After the first successful
apply, authenticate interactively with `tailscale up` (or use the user's existing
secret-management setup). The daemon then rejoins the tailnet automatically on
every boot. The menu-bar GUI is a separate choice (a Homebrew cask); ask the user
whether they also want it.
