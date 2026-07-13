---
id: ai-shared-mcp
title: Shared MCP servers
section: AI Agents
symbol: point.3.connected.trianglepath.dotted
summary: Share Context7 and MCP-NixOS across Codex, Claude Code, and OpenCode.
featured: false
source: https://nix-community.github.io/home-manager/options/home-manager/programs/mcp.html
mcp-verified: 2026-07-14
mcp-query: home-manager options programs.mcp.enable programs.mcp.servers
---

Manage useful MCP servers once through Home Manager, then let each enabled
agent consume the same baseline through its `enableMcpIntegration` option.

```nix
programs.mcp = {
  enable = true;

  servers = {
    # Current library and framework documentation.
    context7 = {
      url = "https://mcp.context7.com/mcp";
    };

    # Cloudflare Workers, platform, and product documentation.
    cloudflare-docs = {
      type = "http";
      url = "https://docs.mcp.cloudflare.com/mcp";
    };

    # Nixpkgs, nix-darwin, and Home Manager option/package lookup.
    nixos = {
      command = "nix";
      args = [ "run" "github:utensils/mcp-nixos" "--" ];
    };
  };
};
```

Enable the matching integration on each client, for example
`programs.codex.enableMcpIntegration = true;`. Context7 is a remote HTTP MCP
server. MCP-NixOS is launched locally by Nix and requires network access on its
first run to obtain the flake input.
