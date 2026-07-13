---
id: font-cjk-emoji
title: CJK & emoji
section: Fonts
symbol: globe
summary: CJK & emoji configuration recipe.
featured: false
mcp-verified: 2026-07-13
mcp-query: nixos packages noto-fonts-cjk-sans noto-fonts-color-emoji
---

Add CJK and emoji coverage: Noto Sans CJK and Noto Color Emoji so nothing renders as tofu boxes.

```nix
{ pkgs, ... }:
{
  fonts.packages = with pkgs; [
    noto-fonts-cjk-sans
    noto-fonts-color-emoji
  ];
}
```
