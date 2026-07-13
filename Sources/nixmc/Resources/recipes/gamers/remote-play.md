---
id: remote-play
title: Remote play
section: For Gamers
symbol: wifi
summary: Remote play configuration recipe.
featured: false
mcp-verified: 2026-07-13
mcp-query: nixos options services.sunshine
---

Set up remote play between my gaming box and Mac with Tailscale, Moonlight/Sunshine, wake-on-LAN where supported, and a shell command to connect.

Two ends. On the NixOS gaming box (the host) enable Tailscale, the Sunshine
stream host, and wake-on-LAN on the wired interface. On the Mac (the client)
install the Moonlight cask (see the Mac gaming recipe). All NixOS options and
packages below are verified against nixpkgs.

```nix
{ ... }:
{
  # Overlay network so the Mac can always reach the box by its Tailscale IP.
  services.tailscale.enable = true;

  # Sunshine host that Moonlight connects to; opens its own firewall ports.
  services.sunshine = {
    enable = true;
    autoStart = true;
    openFirewall = true;
    capSysAdmin = true; # DRM/KMS screen capture
  };

  # Wake the box from sleep with a magic packet. Replace `eno1` with your NIC.
  networking.interfaces.eno1.wakeOnLan.enable = true;
}
```

On the Mac client (Homebrew, via `.nixmc/homebrew/data.json`):

```json
{
  "casks": ["moonlight"]
}
```

Connect and wake from the Mac shell (requires `wakeonlan`, e.g.
`brew install wakeonlan`):

```sh
# Wake the box (replace with the box's MAC address), then launch Moonlight.
wakeonlan AA:BB:CC:DD:EE:FF
open -a Moonlight
```

Notes:

- `services.tailscale.authKeyFile` can be set to a secret path to auto-join the
  tailnet unattended; otherwise run `tailscale up` once to authenticate — this is
  a manual, account-bound step.
- Wake-on-LAN only works over wired Ethernet and must also be enabled in the
  motherboard/BIOS; over Tailscale/Wi-Fi it will not wake a fully powered-off
  machine.
- The `moonlight-qt` client is also packaged in nixpkgs if you prefer to manage
  the Mac client through home-manager instead of Homebrew.
