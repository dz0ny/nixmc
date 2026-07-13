---
mcp-verified: 2026-07-13
mcp-query: "nixos: package nodejs_22, pnpm, uv, go, rustc, cargo"
id: pkg-dev-runtimes
title: Dev runtimes
section: Packages
symbol: chevron.left.forwardslash.chevron.right
summary: Dev runtimes configuration recipe.
featured: false
---

Add developer runtimes and their tooling: Node with pnpm, Python via uv, Go, and Rust with cargo.

```nix
{ pkgs, ... }:
{
  home.packages = with pkgs; [ nodejs_22 pnpm uv go rustc cargo ];
}
```
