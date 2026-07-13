---
id: nixos-gaming-box
title: NixOS gaming box
section: For Gamers
symbol: gamecontroller.fill
summary: NixOS gaming box configuration recipe.
featured: false
mcp-verified: 2026-07-13
mcp-query: nixos options programs.steam
---

For my NixOS gaming box, enable Steam, Gamescope, Gamemode, Sunshine remote play, and Prism Launcher with sensible firewall openings.

This is a Linux/NixOS machine, so edit the NixOS configuration. All options and
packages below are verified against nixpkgs.

```nix
{ pkgs, ... }:
{
  # Steam with firewall openings for Remote Play + local network transfers.
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    localNetworkGameTransfers.openFirewall = true;
    gamescopeSession.enable = true;
  };

  # Gamescope micro-compositor and GameMode performance daemon.
  programs.gamescope = {
    enable = true;
    capSysNice = true;
  };
  programs.gamemode.enable = true;

  # Sunshine host for Moonlight remote play; opens its own firewall ports.
  services.sunshine = {
    enable = true;
    autoStart = true;
    openFirewall = true;
    capSysAdmin = true; # required for DRM/KMS screen capture
  };

  # Launchers and monitoring overlays.
  environment.systemPackages = with pkgs; [
    prismlauncher
    mangohud
    lutris
    heroic
    protonup-qt
  ];
}
```

Notes:

- `programs.steam.remotePlay.openFirewall` and
  `programs.steam.localNetworkGameTransfers.openFirewall` handle Steam's ports;
  `services.sunshine.openFirewall` handles the Moonlight/Sunshine ports, so no
  manual `networking.firewall` rules are needed.
- `capSysNice`/`capSysAdmin` grant the capabilities Gamescope and Sunshine need
  for reniceing and screen capture respectively.
- Enable a GPU with `hardware.graphics.enable = true;` (and vendor drivers) in
  your hardware configuration if not already set.
