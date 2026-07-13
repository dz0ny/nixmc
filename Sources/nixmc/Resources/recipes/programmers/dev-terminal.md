---
id: dev-terminal
title: Dev workstation
section: For Programmers
symbol: terminal
summary: Dev workstation configuration recipe.
featured: false
mcp-verified: 2026-07-13
mcp-query: home-manager options programs.starship / programs.direnv / programs.git
---

Set up my daily coding terminal: enable zsh, starship, direnv with nix-direnv, git with SSH commit signing, lazygit, fzf, ripgrep, fd, jq, and Ghostty with a readable theme.

## Guide

Wire this up through Home Manager so the shell, prompt, and CLI tools travel with the config. The terminal emulator (Ghostty) is a GUI app, so install it as a Homebrew cask through nixmc's brew data rather than through nixpkgs — the nixpkgs `ghostty` build targets Linux and does not build cleanly on macOS.

```nix
{ pkgs, ... }:
{
  # CLI tools live in the user profile.
  home.packages = with pkgs; [
    ripgrep   # rg  — 14.x
    fd        # fd  — fast find
    jq        # jq  — JSON wrangling
    lazygit   # 0.61 — terminal UI for git
  ];

  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
  };

  # Minimal, fast prompt. programs.starship writes ~/.config/starship.toml
  # and hooks the shell init for you.
  programs.starship = {
    enable = true;
    enableZshIntegration = true;
    settings = {
      add_newline = false;
      command_timeout = 1000;
    };
  };

  # Per-directory environments; nix-direnv makes `use flake` fast + cached.
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    enableZshIntegration = true;
  };

  # Fuzzy finder with Ctrl-R / Ctrl-T / Alt-C shell bindings.
  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
  };

  # Git with SSH-based commit signing (no GPG).
  programs.git = {
    enable = true;
    userName = "Your Name";
    userEmail = "you@example.com";
    extraConfig = {
      init.defaultBranch = "main";
      gpg.format = "ssh";
      user.signingkey = "~/.ssh/id_ed25519.pub";
      commit.gpgsign = true;
      tag.gpgsign = true;
    };
  };
}
```

For the Ghostty terminal emulator, add it as a Homebrew cask (nixmc records this in `.nixmc/homebrew/data.json`, consumed by the flake via `builtins.fromJSON`) and drop a readable theme into its config:

```
# ~/.config/ghostty/config
theme = catppuccin-mocha
font-family = JetBrainsMono Nerd Font
font-size = 14
background-opacity = 0.98
```

Ask nixmc to "add the ghostty cask" so the brew data picks it up, then rebuild.

_Verified 2026-07-13 via MCP (source=nixos): starship 1.24.2, nix-direnv 3.1.1, lazygit 0.61.0, ghostty 1.3.1. Home Manager option paths `programs.starship`, `programs.direnv.nix-direnv`, `programs.fzf`, `programs.git` are the current stable module names._
