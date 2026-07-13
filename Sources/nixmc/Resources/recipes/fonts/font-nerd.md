---
id: font-nerd
title: Nerd Fonts
section: Fonts
symbol: terminal
summary: Nerd Fonts configuration recipe.
featured: false
mcp-verified: 2026-07-13
mcp-query: nixos packages nerd-fonts
---

Add Nerd Fonts for my terminal and prompt: JetBrainsMono, FiraCode, and Hack, with glyphs patched in. Modern nixpkgs exposes each patched font under the `nerd-fonts.*` namespace (the old `nerdfonts.override` syntax is gone).

```nix
{ pkgs, ... }:
{
  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
    nerd-fonts.fira-code
    nerd-fonts.hack
  ];
}
```
