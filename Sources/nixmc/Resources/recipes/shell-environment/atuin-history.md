---
mcp-verified: 2026-07-13
mcp-query: "nixos: package atuin"
id: atuin-history
title: Searchable shell history with Atuin
section: Shell & Environment
symbol: text.magnifyingglass
summary: Add Atuin to Zsh for synced, searchable command history.
featured: false
source: https://github.com/zupo/dotfiles/blob/main/common/zsh.nix
---

Install and initialize Atuin for Zsh. Keep normal shared Zsh history enabled,
disable only Atuin's up-arrow binding so the existing shell navigation remains
predictable, and do not configure sync credentials unless the user asks.

```nix
{ pkgs, ... }:
{
  home.packages = [ pkgs.atuin ];

  programs.zsh = {
    history = {
      append = true;
      share = true;
    };
    initContent = ''
      eval "$(atuin init zsh --disable-up-arrow)"
    '';
  };
}
```

## Guide

Atuin provides full-text command-history search and can optionally sync history
between machines. The basic setup stays local. Sign in or configure sync only
when the user explicitly chooses a sync provider and understands which command
history will leave the device.
