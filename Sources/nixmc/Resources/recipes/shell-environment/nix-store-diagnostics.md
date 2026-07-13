---
mcp-verified: manual
mcp-query: not-applicable
id: nix-store-diagnostics
title: Nix storage and diagnostics
section: Shell & Environment
symbol: externaldrive.badge.gearshape
summary: Optimize the Nix store automatically and show more useful build errors.
featured: false
source: https://github.com/zupo/dotfiles/blob/main/darwin/zbook.nix
---

Improve Nix maintenance and troubleshooting on macOS without changing channels,
trusted users, binary caches, or builder configuration. Enable automatic store
optimization and increase error-log context to 25 lines.

```nix
{ ... }:
{
  nix.optimise.automatic = true;
  nix.settings.log-lines = 25;
}
```

Merge this into the nix-darwin system module that owns `nix.*` options. Preserve
any existing values when they are deliberately stricter or more verbose.

## Guide

Automatic store optimization deduplicates identical Nix store files to reduce
disk use. Increasing `log-lines` gives failed builds more context without
changing build behavior. These are system-level nix-darwin options, so they take
effect after the next successful rebuild.
