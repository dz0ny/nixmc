---
id: font-ui
title: UI & document fonts
section: Fonts
symbol: doc.richtext
summary: UI & document fonts configuration recipe.
featured: false
mcp-verified: 2026-07-13
mcp-query: nixos packages inter ibm-plex source-serif
---

Add clean UI and document fonts: Inter, IBM Plex Sans, and Source Serif. IBM Plex Sans ships inside the `ibm-plex` family package.

```nix
{ pkgs, ... }:
{
  fonts.packages = with pkgs; [
    inter
    ibm-plex
    source-serif
  ];
}
```
