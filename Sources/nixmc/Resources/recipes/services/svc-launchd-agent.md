---
mcp-verified: 2026-07-13
mcp-query: "darwin: options launchd.user.agents"
id: svc-launchd-agent
title: Run a maintenance job on a schedule
section: Services
symbol: clock.arrow.circlepath
summary: Run a user-owned maintenance script on a predictable schedule and retain its logs.
featured: false
---

Add a launchd user agent that runs a maintenance script on a schedule and writes rotating logs to ~/Library/Logs.

```nix
launchd.user.agents.nixmc-maintenance = {
  script = "$HOME/.local/bin/nixmc-maintenance";
  serviceConfig = {
    StartCalendarInterval = [{ Hour = 9; Minute = 0; }];
    StandardOutPath = "/Users/USER/Library/Logs/nixmc-maintenance.log";
    StandardErrorPath = "/Users/USER/Library/Logs/nixmc-maintenance.log";
  };
};
```

Replace `USER` and make the maintenance script idempotent.
