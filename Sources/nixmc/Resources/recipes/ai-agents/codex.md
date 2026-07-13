---
id: ai-codex
title: Codex CLI
section: AI Agents
symbol: terminal.badge.sparkles
summary: Install Codex CLI and manage its global instructions with Home Manager.
featured: false
source: https://nix-community.github.io/home-manager/options/home-manager/programs/codex.html
mcp-verified: 2026-07-14
mcp-query: home-manager options programs.codex.enable programs.codex.settings programs.codex.context
---

Install Codex CLI declaratively and keep its global agent instructions in the
Home Manager configuration instead of an unmanaged `~/.codex/AGENTS.md`.

```nix
programs.codex = {
  enable = true;
  enableMcpIntegration = true;

  settings = {
    approval_policy = "on-request";
    sandbox_mode = "workspace-write";
  };

  context = ''
    Prefer small, reviewable changes.
    Run the relevant formatter and tests before finishing work.
  '';
};
```

`settings` is rendered as Codex's `config.toml`; `context` becomes its global
`AGENTS.md`. Pair this with the Shared MCP servers recipe to provide Context7
and MCP-NixOS through the managed `programs.mcp.servers` baseline.
