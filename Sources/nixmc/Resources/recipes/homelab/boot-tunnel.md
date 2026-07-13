---
id: boot-tunnel
title: Boot tunnel
section: For Homelab Admins
symbol: network
summary: Boot tunnel configuration recipe.
featured: false
mcp-verified: 2026-07-13
mcp-query: darwin option launchd.user.agents; nixos package cloudflared
---

Tunnel a local service automatically on boot with Tailscale or cloudflared, add a launchd daemon, and document the local URL in my shell login message.

## Implementation

nix-darwin has **no** `services.cloudflared` module (confirmed: no darwin option
matches `cloudflared`). Run the tunnel as a per-user launchd agent instead. The
`cloudflared` package is in nixpkgs (`pkgs.cloudflared`, 2026.3.0). The
`launchd.user.agents.<name>` option tree — including `command`, `path`, and
`serviceConfig.RunAtLoad` / `serviceConfig.KeepAlive` — is MCP-verified in
nix-darwin.

Point the tunnel at a local service (e.g. `http://localhost:8080`) and start it
at boot:

```nix
{ config, pkgs, ... }:
{
  # cloudflared client (Tunnel / Access / DoH)
  environment.systemPackages = [ pkgs.cloudflared ];

  # Per-user launchd agent that brings the tunnel up on login and keeps it alive.
  launchd.user.agents.homelab-tunnel = {
    command = "${pkgs.cloudflared}/bin/cloudflared tunnel --no-autoupdate run homelab";
    path = [ pkgs.cloudflared ];
    serviceConfig = {
      RunAtLoad = true;   # start on boot/login
      KeepAlive = true;   # restart if it exits
      StandardOutPath = "/tmp/homelab-tunnel.log";
      StandardErrorPath = "/tmp/homelab-tunnel.err.log";
    };
  };
}
```

Document the local URL in the login banner (works with either Tailscale or
cloudflared):

```nix
programs.zsh.loginShellInit = ''
  echo "homelab tunnel → https://homelab.example.com  (local: http://localhost:8080)"
'';
```

### Secrets (supplied out-of-band)

The tunnel **credentials are not managed by Nix** and must never be committed to
the flake. Provision one of:

- A named tunnel + credentials file created with `cloudflared tunnel login` and
  `cloudflared tunnel create homelab`. Reference it via
  `~/.cloudflared/<tunnel-id>.json` and a `~/.cloudflared/config.yml`.
- Or a token tunnel: `cloudflared tunnel --no-autoupdate run --token <TOKEN>`,
  where `<TOKEN>` comes from the Cloudflare Zero Trust dashboard and is injected
  out-of-band (keychain / agenix / sops-nix), not written into this file.

For a Tailscale-based tunnel instead, run `tailscale serve` / `tailscale funnel`
from an equivalent `launchd.user.agents.homelab-tunnel` agent; the auth key is
likewise an out-of-band secret.
