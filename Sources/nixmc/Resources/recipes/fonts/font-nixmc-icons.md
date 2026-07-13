---
id: font-nixmc-icons
title: Icon fonts
section: Fonts
symbol: star
summary: Icon fonts configuration recipe.
featured: false
mcp-verified: 2026-07-13
mcp-query: nixos packages font-awesome material-design-icons
---

Install icon and symbol fonts for my dev setup: Font Awesome and Material Design Icons. Both are packaged in nixpkgs and install cleanly at the system level.

```nix
{ pkgs, ... }:
{
  fonts.packages = with pkgs; [
    font-awesome
    material-design-icons
  ];
}
```
