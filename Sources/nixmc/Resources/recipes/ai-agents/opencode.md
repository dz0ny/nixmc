---
id: ai-opencode
title: OpenCode
section: AI Agents
symbol: chevron.left.forwardslash.chevron.right
summary: Install OpenCode with managed settings, TUI preferences, and global context.
featured: false
source: https://nix-community.github.io/home-manager/options/home-manager/programs/opencode.html
mcp-verified: 2026-07-14
mcp-query: home-manager options programs.opencode.enable programs.opencode.settings programs.opencode.tui programs.opencode.context
---

Install OpenCode declaratively and manage its JSON configuration, TUI settings,
and global `AGENTS.md` through Home Manager.

```nix
programs.opencode = {
  enable = true;
  enableMcpIntegration = true;

  settings = {
    autoshare = false;
    autoupdate = true;
  };

  tui = {
    theme = "system";
  };

  context = ''
    Prefer focused changes with a clear verification step.
  '';
};
```

Home Manager writes `settings` to `opencode.json`, keeps TUI-only preferences
in `tui.json`, and writes `context` as OpenCode's global `AGENTS.md`. Use
the Shared MCP servers recipe to provide Context7 and MCP-NixOS through
`programs.mcp.servers`.
