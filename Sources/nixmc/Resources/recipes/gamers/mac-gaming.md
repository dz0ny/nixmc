---
id: mac-gaming
title: Mac gaming
section: For Gamers
symbol: gamecontroller
summary: Mac gaming configuration recipe.
featured: false
mcp-verified: 2026-07-13
mcp-query: nixos packages moonlight-qt
---

Install my Mac gaming basics: Steam, Discord, Prism Launcher, Moonlight, controller utilities, and a Finder folder for game captures.

On macOS these are all GUI apps, so add them as Homebrew casks in
`.nixmc/homebrew/data.json` — not a Nix module. Add only the requested casks and
preserve any existing activation policy.

```json
{
  "casks": ["steam", "discord", "prismlauncher", "moonlight", "sdl2"],
  "onActivation": { "autoUpdate": true, "upgrade": true, "cleanup": "uninstall" }
}
```

Notes:

- `steam`, `discord`, `prismlauncher` (Minecraft launcher), and `moonlight`
  (Sunshine/Moonlight streaming client) are all real Homebrew casks.
- Controller support on macOS is handled natively (Xbox/PlayStation controllers
  pair over Bluetooth via System Settings); no cask is required. If you want SDL
  gamepad tooling, keep it as a CLI in `home.packages` (`pkgs.SDL2`) instead of a
  cask.
- The "game captures" folder is a plain Finder directory (e.g.
  `~/Movies/Game Captures`) created via `home.activation` or by hand — it is not a
  package.

Cross-reference: the `moonlight-qt` client is also available on the Nix side
(nixpkgs `moonlight-qt`) if you later manage the Mac via home-manager packages
instead of Homebrew.
