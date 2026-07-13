---
mcp-verified: 2026-07-13
mcp-query: "nixos: package starship"
id: env-prompt-git
title: Git-aware prompt
section: Shell & Environment
symbol: arrow.branch
summary: Git-aware prompt configuration recipe.
featured: false
---

Configure my prompt (starship) to show git branch, dirty state, and command duration for long-running commands.

```nix
{ pkgs, ... }:
{
  home.packages = [ pkgs.starship ];
}
```
