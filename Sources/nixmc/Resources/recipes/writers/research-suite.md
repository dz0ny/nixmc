---
mcp-verified: 2026-07-13
mcp-query: "nixos: package pandoc, texliveFull, zotero, anki"
id: research-suite
title: Research suite
section: For Writers & Researchers
symbol: book
summary: Research suite configuration recipe.
featured: false
---

Set up Obsidian vault defaults, pandoc, TeX Live, Zotero, Anki, citation styles, and a clean PDF reading workflow.

```nix
{ pkgs, ... }:
{
  home.packages = with pkgs; [ pandoc texliveFull zotero anki ];
}
```
