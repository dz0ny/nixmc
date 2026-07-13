---
id: pkg-cloud-cli
title: Cloud CLIs
section: Packages
symbol: cloud
summary: Cloud CLIs configuration recipe.
featured: false
mcp-verified: 2026-07-13
mcp-query: nixos packages google-cloud-sdk
---

Install cloud provider CLIs through Home Manager. Add these to `home.packages`
in `home.nix`.

```nix
{ pkgs, ... }:
{
  home.packages = with pkgs; [
    awscli2
    google-cloud-sdk
    azure-cli
    doctl
    flyctl
    kubectl
    opentofu
  ];
}
```

`opentofu` is the open-source, MPL-licensed drop-in for Terraform. If you
specifically need HashiCorp's `terraform`, note it is unfree (BUSL) and requires
`nixpkgs.config.allowUnfree = true`.
