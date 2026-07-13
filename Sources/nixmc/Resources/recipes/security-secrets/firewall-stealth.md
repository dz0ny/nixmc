---
mcp-verified: 2026-07-13
mcp-query: "darwin: options networking.applicationFirewall"
id: firewall-stealth
title: Enable firewall stealth mode
section: Security & Secrets
symbol: shield.lefthalf.filled
summary: Keep the macOS application firewall enabled and avoid responding to unsolicited probes.
featured: false
source: https://github.com/nix-darwin/nix-darwin
---

Use nix-darwin's firewall settings in the system module. Do not disable the
firewall to work around an application issue; add only the required exception
after identifying the application and port.

```nix
networking.applicationFirewall = {
  enable = true;
  enableStealthMode = true;
  blockAllIncoming = false;
};
```

Preserve existing firewall options and explain any security trade-off before
changing `enableBlockAll`.
