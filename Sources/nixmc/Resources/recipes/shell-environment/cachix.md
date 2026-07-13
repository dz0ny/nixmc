---
mcp-verified: 2026-07-13
mcp-query: "nixos: package cachix"
id: cachix
title: Configure Cachix binary caches
section: Shell & Environment
symbol: externaldrive.badge.checkmark
summary: Use trusted Cachix binary caches to avoid rebuilding project dependencies locally.
featured: false
source: https://github.com/cachix/cachix
---

Install the Cachix CLI in the user profile. Configure only caches whose URL and
public key the user has verified from the project or cache owner; never put a
Cachix authentication token in a Nix file or `GUIDE.md`.

```nix
{ pkgs, ... }:
{
  home.packages = [ pkgs.cachix ];
}
```

For a project-specific cache, add the verified substituter and public key to the
Nix settings owned by this configuration:

```nix
nix.settings = {
  extra-substituters = [ "https://CACHE_NAME.cachix.org" ];
  extra-trusted-public-keys = [ "CACHE_NAME.cachix.org-1:PUBLIC_KEY" ];
};
```

Replace both placeholders with values supplied by the cache owner. Authenticate
with `cachix authtoken` only when the user explicitly wants to push builds, and
store the token in the user's credential store rather than the repository.

## Guide

Cachix lets Nix download verified prebuilt outputs from approved project caches.
Only the configured cache URL and its public signing key are trusted; publishing
credentials remain outside the declarative configuration.
