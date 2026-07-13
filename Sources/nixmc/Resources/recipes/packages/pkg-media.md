---
mcp-verified: 2026-07-13
mcp-query: "nixos: package ffmpeg, yt-dlp, imagemagick, mpv, mediainfo"
id: pkg-media
title: Media tools
section: Packages
symbol: play.rectangle
summary: Media tools configuration recipe.
featured: false
---

Install media and download tools: ffmpeg, yt-dlp, imagemagick, mpv, and mediainfo.

```nix
{ pkgs, ... }:
{
  home.packages = with pkgs; [ ffmpeg yt-dlp imagemagick mpv mediainfo ];
}
```
