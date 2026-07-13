---
mcp-verified: 2026-07-13
mcp-query: "nixos: package mise"
id: env-mise
title: Per-project tool versions
section: Shell & Environment
symbol: list.number
summary: Per-project tool versions configuration recipe.
featured: false
---

Set up mise (or asdf) so each project can pin its own Node/Python/Ruby version via a config file.

```nix
{ pkgs, ... }:
{
  home.packages = [ pkgs.mise ];
}
```
