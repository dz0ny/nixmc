---
id: ai-peon-sounds
title: Warcraft Peon Sounds
section: AI Agents
symbol: speaker.wave.2
summary: Play a random Warcraft peon sound when Claude Code finishes and waits for input.
featured: false
source: https://github.com/zupo/dotfiles/commit/63c622b95e943f912a299cbb3ce535779d6f42a3
---

Add a Claude Code `Stop` hook that plays a random Warcraft peon voice line
("Work complete!", "Ready to work?") whenever Claude finishes a turn and is
waiting for input. The sounds are fetched from the source dotfiles repo and
packaged as a small derivation, so nothing is downloaded at runtime.

This extends `programs.claude-code.settings` — merge the hook into any
existing settings instead of replacing them.

```nix
{ pkgs, ... }:
let
  peonSounds = pkgs.stdenvNoCC.mkDerivation {
    name = "peon-sounds";
    src = pkgs.fetchFromGitHub {
      owner = "zupo";
      repo = "dotfiles";
      rev = "63c622b95e943f912a299cbb3ce535779d6f42a3";
      hash = "sha256-aiFhPJEZ3KfobrKkQ2PDF5M3ehNpFlcIIAAPKWA4ets=";
    };
    installPhase = ''
      mkdir -p $out
      cp sounds/*.ogg $out/
    '';
  };
in
{
  programs.claude-code.settings = {
    # Play a random Warcraft peon sound when Claude is waiting for input.
    hooks.Stop = [
      {
        hooks = [
          {
            type = "command";
            command = "afplay $(ls ${peonSounds}/*.ogg | sort -R | head -1) &";
          }
        ];
      }
    ];
  };
}
```

Requires `programs.claude-code.enable = true` (see the Claude Code recipe).
`afplay` ships with macOS, so no extra packages are needed.
