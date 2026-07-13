---
id: font-handwriting
title: Handwriting & display
section: Fonts
symbol: pencil.and.scribble
summary: Handwriting & display configuration recipe.
featured: false
mcp-verified: 2026-07-13
mcp-query: nixos packages lexend google-fonts
---

Add a couple of handwriting/display fonts for notes and presentations: Caveat and Lexend. Caveat is not packaged standalone in nixpkgs — it ships inside the `google-fonts` bundle, so pull that in for Caveat and use the standalone `lexend` package.

```nix
{ pkgs, ... }:
{
  fonts.packages = with pkgs; [
    lexend
    google-fonts   # provides Caveat (and many others)
  ];
}
```
