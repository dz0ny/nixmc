---
id: font-coding
title: Coding font
section: Fonts
symbol: chevron.left.forwardslash.chevron.right
summary: Coding font configuration recipe.
featured: false
mcp-verified: 2026-07-13
mcp-query: nixos packages monaspace ibm-plex
---

Install a crisp coding font — Monaspace (or IBM Plex Mono) — and note it so I can set it as my editor and terminal default. IBM Plex Mono ships inside the `ibm-plex` family package.

```nix
{ pkgs, ... }:
{
  fonts.packages = with pkgs; [
    monaspace
    ibm-plex
  ];
}
```

Do not change terminal or editor preference files unless explicitly asked.
