---
mcp-verified: manual
mcp-query: not-applicable
id: direnv
title: Enable direnv with nix-direnv
section: Shell & Environment
symbol: folder.badge.gearshape
summary: Load reproducible project development shells automatically when entering a directory.
featured: false
source: https://github.com/wochap/nix-config/blob/main/modules/shared/programs/cli/nix-direnv/default.nix
---

Enable the Home Manager modules in `home.nix`. This belongs in the user profile,
not in system-wide shell initialization.

```nix
programs.direnv = {
  enable = true;
  nix-direnv.enable = true;
};
```

For a project using flakes, the local `.envrc` can be exactly:

```sh
use flake
```

Never automatically allow an unreviewed `.envrc`; the user should run
`direnv allow` inside each trusted project.
