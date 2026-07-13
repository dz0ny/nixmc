---
id: font-office
title: Office compatibility
section: Fonts
symbol: doc.on.doc
summary: Office compatibility configuration recipe.
featured: false
mcp-verified: 2026-07-13
mcp-query: nixos packages liberation_ttf carlito
---

Add fonts for compatibility with Word/Excel documents from Windows users: Liberation (metric-compatible with Arial/Times/Courier) and Carlito (metric-compatible with Calibri).

```nix
{ pkgs, ... }:
{
  fonts.packages = with pkgs; [
    liberation_ttf
    carlito
  ];
}
```
