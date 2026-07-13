---
id: pkg-containers
title: Container tooling
section: Packages
symbol: shippingbox.fill
summary: Container tooling configuration recipe.
featured: false
mcp-verified: 2026-07-13
mcp-query: nixos packages kubernetes-helm
---

Install container and Kubernetes tooling through Home Manager. Add these to
`home.packages` in `home.nix`.

```nix
{ pkgs, ... }:
{
  home.packages = with pkgs; [
    colima          # container runtime VM (Docker Desktop alternative)
    docker-client   # the `docker` CLI, points at colima's socket
    lazydocker
    dive
    kubectl
    kubernetes-helm # provides `helm`
    k9s
    kubecolor
  ];
}
```

On macOS the Docker daemon needs a Linux VM: `colima` provides it and
`docker-client` gives you the `docker` CLI. Start it with `colima start`.
Docker Desktop itself is a GUI app distributed as a Homebrew cask
(`docker-desktop`), not a nixpkgs package.
