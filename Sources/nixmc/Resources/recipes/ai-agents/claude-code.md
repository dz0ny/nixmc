---
id: ai-claude-code
title: Claude Code
section: AI Agents
symbol: sparkles.rectangle.stack
summary: Install Claude Code and manage settings and global context with Home Manager.
featured: false
source: https://nix-community.github.io/home-manager/options/home-manager/programs/claude-code.html#opt-programs.claude-code.enable
mcp-verified: 2026-07-14
mcp-query: home-manager options programs.claude-code.enable programs.claude-code.settings programs.claude-code.context
---

Install Claude Code declaratively, define a cautious default permission mode,
and put lasting instructions in the managed global `CLAUDE.md`.

```nix
programs.claude-code = {
  enable = true;
  enableMcpIntegration = true;

  settings = {
    permissions = {
      defaultMode = "acceptEdits";
      ask = [ "Bash(git push:*)" ];
    };
  };

  context = ''
    Keep configuration changes declarative and explain notable trade-offs.
    Do not commit or push unless explicitly requested.
  '';
};
```

Home Manager writes settings to Claude Code's managed configuration directory
and writes `context` as `CLAUDE.md`. Pair this with the Shared MCP servers
recipe to provide Context7 and MCP-NixOS through `programs.mcp.servers`.
