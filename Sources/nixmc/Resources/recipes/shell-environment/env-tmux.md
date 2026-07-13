---
mcp-verified: 2026-07-13
mcp-query: "nixos: package tmux"
id: env-tmux
title: tmux workflow
section: Shell & Environment
symbol: square.split.2x2
summary: tmux workflow configuration recipe.
featured: false
---

Enable tmux with sensible defaults: mouse support, vi keybindings, a readable status bar, and a prefix I don't have to fight.

```nix
{ pkgs, ... }:
{
  home.packages = [ pkgs.tmux ];
}
```
