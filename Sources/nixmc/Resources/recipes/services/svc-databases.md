---
mcp-verified: 2026-07-13
mcp-query: "darwin: options services.postgresql, services.redis"
id: svc-databases
title: Start local development databases
section: Services
symbol: cylinder.split.1x2
summary: Start PostgreSQL and Redis at login, bound locally for development work.
featured: false
---

Run PostgreSQL and Redis as local nix-darwin services for development, started at login.

```nix
services.postgresql = {
  enable = true;
  enableTCPIP = false;
};

services.redis = {
  enable = true;
  bind = "127.0.0.1";
};
```
