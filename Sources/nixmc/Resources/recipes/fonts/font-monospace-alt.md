---
id: font-monospace-alt
title: Alternate monospace
section: Fonts
symbol: text.alignleft
summary: Alternate monospace configuration recipe.
featured: false
mcp-verified: 2026-07-13
mcp-query: nixos packages cascadia-code iosevka victor-mono
---

Add a few alternate monospace fonts to compare for coding: Cascadia Code, Iosevka, and Victor Mono.

```nix
{ pkgs, ... }:
{
  fonts.packages = with pkgs; [
    cascadia-code
    iosevka
    victor-mono
  ];
}
```
