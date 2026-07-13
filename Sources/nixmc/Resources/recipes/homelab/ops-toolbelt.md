---
id: ops-toolbelt
title: Ops toolbelt
section: For Homelab Admins
symbol: wrench.and.screwdriver
summary: Ops toolbelt configuration recipe.
featured: false
mcp-verified: 2026-07-13
mcp-query: nixos package k9s kubecolor jq yq-go dig iperf nmap
---

Install and configure lightweight ops tools: k9s, kubecolor, jq, yq, dig, iperf3, nmap, and a quick network diagnostics shell alias.

## Implementation

Add the CLI tools through Home Manager `home.packages`. Every attribute below is
MCP-verified against nixpkgs (nixos source):

| Tool requested | Verified nixpkgs attr | Version |
|----------------|-----------------------|---------|
| k9s            | `k9s`                 | 0.50.18 |
| kubecolor      | `kubecolor`           | 0.5.3   |
| jq             | `jq`                  | 1.8.1   |
| yq             | `yq-go`               | 4.52.5  |
| dig            | `dig` (from `bind`)   | 9.20.22 |
| iperf3         | `iperf`               | 3.20    |
| nmap           | `nmap`                | 7.99    |

Note: nixpkgs ships iperf 3.x under the attribute `iperf` (there is no `iperf3`
attribute); `dig` resolves to the `dig` output of the `bind` package.

```nix
{ pkgs, ... }:
{
  home.packages = with pkgs; [
    k9s        # Kubernetes TUI
    kubecolor  # colorized kubectl output
    jq         # JSON processor
    yq-go      # YAML processor
    dig        # DNS lookups (from bind)
    iperf      # iperf3 bandwidth tester
    nmap       # network/port scanner
  ];

  # Quick network diagnostics alias.
  programs.zsh.shellAliases = {
    netcheck = "echo '== dns =='; dig +short example.com; echo '== route =='; ping -c1 1.1.1.1; echo '== ports =='; nmap -F localhost";
    kubectl = "kubecolor";  # colorize kubectl transparently
  };
}
```

If you use the same tools system-wide instead of per-user, put the same list in
`environment.systemPackages` in the nix-darwin config rather than
`home.packages`.
