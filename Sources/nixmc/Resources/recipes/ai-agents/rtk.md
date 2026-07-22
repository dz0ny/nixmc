---
id: ai-rtk
title: RTK Token Killer
section: AI Agents
symbol: chart.line.downtrend.xyaxis
summary: Install rtk and auto-rewrite Claude Code's shell commands to cut tool-output tokens 60-90%.
featured: false
source: https://github.com/rtk-ai/rtk
mcp-verified: 2026-07-22
mcp-query: nixpkgs rtk package; home-manager programs.claude-code.settings hooks PreToolUse
---

Install [rtk](https://github.com/rtk-ai/rtk) (a single Rust binary) and wire its
Claude Code hook declaratively. rtk is a CLI proxy that filters and compresses
command output — `git status`, `ls`, `grep`, test runners, `docker ps`, and 100+
others — before it reaches the model, trimming 60-90% of the tokens those tool
calls would otherwise spend.

The hook is a `PreToolUse` matcher on `Bash` that runs `rtk hook claude`, exactly
what `rtk init -g` writes into `settings.json` — but here it lives in Nix instead
of a mutated dotfile. rtk transparently rewrites each Bash command (e.g.
`git status` → `rtk git status`) before it executes; the agent gets the compact
output without ever calling `rtk` itself.

This extends `programs.claude-code.settings` — merge the hook into any existing
settings (permissions, other hooks) instead of replacing them.

```nix
{ pkgs, ... }:
{
  # rtk is packaged in nixpkgs; put it on the user's PATH.
  home.packages = [ pkgs.rtk ];

  programs.claude-code.settings = {
    # Rewrite every Bash tool call through rtk before it runs.
    hooks.PreToolUse = [
      {
        matcher = "Bash";
        hooks = [
          {
            type = "command";
            command = "${pkgs.rtk}/bin/rtk hook claude";
          }
        ];
      }
    ];
  };
}
```

Requires `programs.claude-code.enable = true` (see the Claude Code recipe).
Referencing `${pkgs.rtk}/bin/rtk` by store path keeps the hook working even when
the menu-bar app's minimal PATH doesn't include the Home Manager profile.

Notes:

- The hook only fires on the `Bash` tool. Claude Code's built-in `Read`, `Grep`,
  and `Glob` bypass it — use shell equivalents (`cat`/`rg`/`find`) or `rtk read`,
  `rtk grep`, `rtk find` when you want rtk filtering there.
- After applying and running `darwin-rebuild switch`, restart Claude Code so it
  reloads settings. Verify with `rtk gain` (savings stats) and by watching a
  command like `git status` come back compact.
- Optional config lives at `~/Library/Application Support/rtk/config.toml`
  (`exclude_commands`, tee-on-failure). It's user data, not Nix — leave it out of
  the flake unless you want it managed via `home.file`.
