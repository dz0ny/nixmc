---
mcp-verified: manual
mcp-query: not-applicable
id: adopt-nixmc-module-layout
title: Adopt the NixMC module layout
section: For Programmers
symbol: rectangle.3.group
summary: Reorganize an existing nix-darwin flake into NixMC’s supported modules without changing behavior.
featured: false
source: https://github.com/nix-darwin/nix-darwin
---

Refactor the current nix-darwin and Home Manager configuration to NixMC’s
supported layout. This is an organizational migration only: preserve existing
options, values, flake inputs, lock file, host name, and user names. Do not add
new packages or change the machine’s behavior.

First inspect the current `flake.nix`, imports, Homebrew settings, and user
modules. Build the existing configuration before moving files when possible.
Then create and import this layout, moving each existing declaration to the
matching module:

```text
modules/
├── darwin/
│   ├── default.nix
│   ├── packages.nix
│   ├── fonts.nix
│   ├── macos-settings.nix
│   ├── services.nix
│   └── security-secrets.nix
└── home/
    ├── default.nix
    ├── shell-environment.nix
    └── ai-agents.nix
```

`modules/darwin/default.nix` must import every Darwin child module, and
`modules/home/default.nix` must import the two Home Manager child modules.
Update `flake.nix` only as needed to import `./modules/darwin`, the NixMC
Homebrew module, and `./modules/home` for the existing primary user.

Move Homebrew `taps`, `brews`, `casks`, and `onActivation` values into
`.nixmc/homebrew/data.json`, preserving every existing value. Keep any advanced
Homebrew options that cannot be represented in that JSON in the Nix module so
the effective configuration remains unchanged. Add or update `CLAUDE.md` with
the NixMC module map so future agents edit the appropriate module.

Use `git mv` where it preserves history. Remove obsolete imports only after the
replacement module is imported. Format the moved files and finish by running
`darwin-rebuild build --flake .#<existing-host-name>`. Compare the result with
the baseline; if the migration changes behavior or does not build, stop and
explain the difference instead of applying it.
