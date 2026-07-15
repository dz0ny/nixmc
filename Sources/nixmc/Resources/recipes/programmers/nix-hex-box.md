---
mcp-verified: manual
mcp-query: not-applicable
id: nix-hex-box
title: Add a HexBox Linux container builder
section: For Programmers
symbol: shippingbox.fill
summary: Use an Apple Container-backed Linux remote builder for Nix on Apple Silicon.
featured: false
source: https://github.com/RobertDeRose/nix-hex-box
---

Add [nix-hex-box](https://github.com/RobertDeRose/nix-hex-box) as an
Apple-Silicon-only remote builder. It manages a persistent `aarch64-linux`
Apple Container machine and configures Nix to use it through `ssh-ng`. Do not
use this recipe on an Intel Mac. Review the upstream project status and its
privileged host integration before applying it.

Add the input in `flake.nix`, pass it through the outputs arguments, and import
its Darwin module alongside the existing NixMC modules. Preserve all existing
flake inputs and module imports:

```nix
inputs.hexbox.url = "github:RobertDeRose/nix-hex-box";

# In darwinConfigurations.<host>.modules:
hexbox.darwinModules.default
```

Configure the builder in `modules/darwin/services.nix`. Start with conservative
resource limits and keep the Docker-compatible Socktainer API off unless it is
needed:

```nix
{ ... }:
{
  services.container-builder = {
    enable = true;
    cpus = 4;
    memory = "8G";
    maxJobs = 4;
    socktainer.enable = false;
    # `user` normally follows config.system.primaryUser.
  };
}
```

Build before applying. After activation, verify the machine and a remote Nix
build with `hb builder repair` followed by `hb builder test`. Use
`hb builder status` to inspect it later. If the Docker-compatible API is
required, enable `socktainer` explicitly and set `DOCKER_HOST` only in the
user’s shell environment; do not replace an existing container runtime without
the user’s approval.

## Guide

HexBox gives an Apple Silicon Mac an `aarch64-linux` Nix builder without using
an ephemeral container. Nix reaches the persistent Apple Container machine
through an SSH proxy, so Linux build outputs and downloaded substitutes survive
machine stops and starts.

Use `hb builder status` for a quick health check. Run `hb builder repair` if
the runtime, machine, or SSH connection needs recovery, then use
`hb builder test` to confirm that remote Nix builds work. `hb builder reset`
recreates the builder and deletes its guest-local `/nix` store, so use it only
when a clean builder is intended.

Socktainer is optional. When enabled, it exposes a Docker-compatible socket at
`~/.socktainer/container.sock`; set `DOCKER_HOST` only for shells that should
use that socket.
