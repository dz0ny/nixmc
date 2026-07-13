---
mcp-verified: 2026-07-13
mcp-query: "nixos: package devenv, direnv, nix-direnv"
id: devenv
title: Set up devenv project environments
section: Shell & Environment
symbol: shippingbox
summary: Install devenv and create reproducible, project-local development shells.
featured: false
source: https://github.com/cachix/devenv
---

Install `devenv` in the user profile and keep project environments in each
project repository. Do not put project-specific language versions, services, or
secrets in the Mac-wide configuration.

```nix
{ pkgs, ... }:
{
  home.packages = [ pkgs.devenv ];

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
}
```

For a new project, use `devenv init`, then start with a small `devenv.nix`:

```nix
{ pkgs, ... }:
{
  packages = [ pkgs.git ];
  languages.python.enable = true;
}
```

Enter it with `devenv shell`, or add `use devenv` to the project `.envrc` and
explicitly run `direnv allow` after reviewing the file.

## Guide

Projects can define their own reproducible tools, language runtimes, and local
services with `devenv.nix`. Entering a trusted project through direnv activates
that project environment without changing the global Mac profile.
