---
mcp-verified: 2026-07-13
mcp-query: "nixos: options services.pipewire"
id: linux-stream-rig
title: Linux stream rig
section: For Streamers
symbol: dot.radiowaves.left.and.right
summary: Linux stream rig configuration recipe.
featured: false
---

For NixOS hosts in this flake, enable OBS Studio, GPU Screen Recorder, PipeWire/JACK, and GoXLR Utility for a dedicated streaming rig.

```nix
{ pkgs, ... }:
{
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    jack.enable = true;
  };

  environment.systemPackages = with pkgs; [
    obs-studio gpu-screen-recorder goxlr-utility
  ];
}
```
