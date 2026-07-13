---
id: pkg-cli-kit
title: Essential CLI kit
section: Packages
symbol: terminal
summary: Essential CLI kit configuration recipe.
featured: false
mcp-verified: 2026-07-13
mcp-query: nixos packages yq-go
---

Install a modern CLI toolkit through Home Manager. Add these to `home.packages`
in `home.nix`, keeping any existing packages. Note the JSON/YAML processor
attribute is `yq-go` (not `yq`, which is the Python wrapper).

```nix
{ pkgs, ... }:
{
  home.packages = with pkgs; [
    ripgrep fd fzf bat eza zoxide
    jq yq-go htop
  ];
}
```
