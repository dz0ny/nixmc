---
id: ssh-homelab
title: SSH homelab
section: For Homelab Admins
symbol: server.rack
summary: SSH homelab configuration recipe.
featured: false
mcp-verified: manual
mcp-query: not-applicable
---

Set up SSH profiles for my homelab machines with ControlMaster, keepalives, known-hosts hashing, and short aliases for each server.

## Implementation

This recipe is fundamentally about **user-specific secrets and topology** —
per-host aliases, hostnames/IPs, usernames, and private key material — so it is
marked `manual`. (The Home Manager MCP data source was also unavailable at audit
time: `home-manager` search/browse/stats all returned empty or errored, so the
`programs.ssh.*` option paths below could not be machine-confirmed and follow the
established Home Manager `programs.ssh` schema.)

Keep the verifiable structure — `programs.ssh.enable` plus `matchBlocks` — and
supply the real hostnames and identity files yourself. Private keys stay on disk
(or in an agent) and are never written into the flake.

```nix
{ ... }:
{
  programs.ssh = {
    enable = true;

    # Global defaults: multiplex connections, keep them alive, hash known_hosts.
    controlMaster = "auto";
    controlPath = "~/.ssh/control/%r@%h:%p";
    controlPersist = "10m";
    serverAliveInterval = 60;
    serverAliveCountMax = 3;
    hashKnownHosts = true;

    # One matchBlock per homelab machine — short alias -> real host.
    # Replace hostnames/IPs, users, and identityFile paths with your own.
    matchBlocks = {
      "nas" = {
        hostname = "10.0.0.10";          # user-specific
        user = "admin";                  # user-specific
        identityFile = "~/.ssh/id_ed25519"; # private key: out-of-band, on disk
      };
      "media" = {
        hostname = "10.0.0.11";
        user = "admin";
        identityFile = "~/.ssh/id_ed25519";
      };
      "build" = {
        hostname = "10.0.0.12";
        user = "root";
        identityFile = "~/.ssh/id_ed25519";
        forwardAgent = true;
      };
    };
  };
}
```

Create the control socket directory once (`mkdir -p ~/.ssh/control`). The private
keys referenced by `identityFile` are supplied out-of-band and must never be
committed to the flake.
