---
id: terminal-theme
title: Terminal theme
section: For Designers
symbol: paintbrush
summary: Terminal theme configuration recipe.
featured: false
mcp-verified: 2026-07-13
mcp-query: nixos packages ghostty bat vivid fzf coreutils
---

Give my terminal and CLI tools a consistent theme: Ghostty, bat, vivid, dircolors, fzf, and a clean prompt that works in light and dark macOS modes.

Install the tools through Home Manager. `dircolors` ships inside `coreutils`; drive `LS_COLORS` from `vivid`, and theme the Ghostty/bat colors to match. Set the actual theme values in each tool's own config (Ghostty config, `BAT_THEME`, `vivid generate`) so they track the macOS light/dark appearance:

```nix
home.packages = with pkgs; [
  ghostty
  bat
  vivid
  fzf
  coreutils
];
```
