---
mcp-verified: 2026-07-13
mcp-query: "nixos: package zoxide"
id: env-aliases
title: Handy aliases
section: Shell & Environment
symbol: text.append
summary: Handy aliases configuration recipe.
featured: false
---

Add handy shell aliases: g/gs/gc/gp for git, ll/la for eza, cat→bat, and cd→zoxide.

```nix
{ pkgs, ... }:
{
  home.packages = [ pkgs.zoxide ];
}
```
