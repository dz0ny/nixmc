---
id: cli-toolbox
title: Add a modern CLI toolbox
section: Packages
symbol: terminal
summary: Add dependable search, JSON, navigation, and Git tools through Home Manager.
featured: true
source: https://github.com/nix-community/home-manager
mcp-verified: 2026-07-13
mcp-query: nixos packages yq-go
---

Add these tools to `home.packages` in `home.nix`. Keep existing packages and
avoid adding Homebrew copies of command-line tools that Nix can own.

```nix
{ pkgs, ... }:
{
  home.packages = with pkgs; [
    ripgrep fd fzf bat eza zoxide
    jq yq-go htop lazygit delta
  ];
}
```

After adding the packages, enable the corresponding Home Manager programs when
they are available, rather than maintaining duplicated aliases by hand.
