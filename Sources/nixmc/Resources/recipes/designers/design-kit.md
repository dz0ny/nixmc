---
id: design-kit
title: Design kit
section: For Designers
symbol: paintpalette
summary: Design kit configuration recipe.
featured: false
mcp-verified: 2026-07-13
mcp-query: darwin options system.defaults.screencapture / system.defaults.finder
---

Install design apps and fonts: Figma, Blender, ImageOptim, SF Mono or Nerd Fonts; set screenshots to ~/Pictures/Screenshots as PNG without shadows; show Finder path and status bars.

GUI apps (Figma, ImageOptim) ship as Homebrew casks via the nixmc JSON — add them to `.nixmc/homebrew/data.json`:

```json
{
  "casks": ["figma", "imageoptim"]
}
```

Blender is packaged in nixpkgs, and fonts install through Home Manager. SF Mono is Apple-provided (not in nixpkgs), so use a Nerd Font as the drop-in monospace face:

```nix
home.packages = with pkgs; [ blender ];

fonts.packages = with pkgs; [
  nerd-fonts.jetbrains-mono
  nerd-fonts.symbols-only
];
```

Put the macOS defaults in the nix-darwin module (create ~/Pictures/Screenshots first). Preserve existing attributes:

```nix
system.defaults.screencapture = {
  location = "~/Pictures/Screenshots";
  type = "png";
  disable-shadow = true;
};

system.defaults.finder = {
  ShowPathbar = true;
  ShowStatusBar = true;
};
```
