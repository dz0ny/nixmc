---
mcp-verified: 2026-07-13
mcp-query: "nixos: package lazygit, delta, git-lfs"
id: pkg-git-tools
title: Git tooling
section: Packages
symbol: point.3.connected.trianglepath.dotted
summary: Git tooling configuration recipe.
featured: false
---

Install Git tooling: lazygit, gh (GitHub CLI), git-delta for diffs, and git-lfs.

```nix
{ pkgs, ... }:
{
  home.packages = with pkgs; [ lazygit delta git-lfs ];
}
```

Install `gh` through the existing Homebrew integration when targeting macOS.
