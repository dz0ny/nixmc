---
mcp-verified: 2026-07-13
mcp-query: "nixos: package direnv, nix-direnv"
id: env-direnv
title: direnv per project
section: Shell & Environment
symbol: folder.badge.gearshape
summary: direnv per project configuration recipe.
featured: false
---

Set up direnv with nix-direnv so project shells load automatically, and add a .envrc template for new repos.

```nix
{ pkgs, ... }:
{
  home.packages = with pkgs; [ direnv nix-direnv ];
}
```
