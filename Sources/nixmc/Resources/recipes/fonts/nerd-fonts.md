---
id: nerd-fonts
title: Install coding and Nerd Fonts
section: Fonts
symbol: textformat
summary: Make terminal, editor, and prompt fonts available system-wide.
featured: false
source: https://github.com/nix-darwin/nix-darwin
mcp-verified: 2026-07-13
mcp-query: nixos packages nerd-fonts inter
---

Add fonts at the system level. Check the package names against the pinned
Nixpkgs revision before applying, because Nerd Font package names can change.

```nix
{ pkgs, ... }:
{
  fonts.packages = with pkgs; [
    nerd-fonts.fira-code
    nerd-fonts.jetbrains-mono
    inter
  ];
}
```

Do not change terminal or editor preference files unless the user explicitly
asks for those application settings.
