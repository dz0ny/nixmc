---
mcp-verified: 2026-07-13
mcp-query: "nixos: package obs-studio, streamlink, twitch-tui, discord"
id: streaming-apps
title: OBS setup
section: For Streamers
symbol: video
summary: OBS setup configuration recipe.
featured: false
---

Install OBS Studio, Streamlink, yt-dlp, Twitch TUI, Discord, and a launchd login agent that prepares a recording folder and opens my stream checklist.

```nix
{ pkgs, ... }:
{
  home.packages = with pkgs; [
    obs-studio streamlink yt-dlp twitch-tui discord
  ];
}
```
