---
mcp-verified: 2026-07-13
mcp-query: "darwin: options launchd.user.agents"
id: login-maintenance
title: Add a scheduled user maintenance job
section: Services
symbol: clock.arrow.circlepath
summary: Run a small user-owned script on a predictable schedule with launchd.
featured: false
source: https://github.com/nix-darwin/nix-darwin
---

Create a user launch agent rather than a root daemon for user-home maintenance.
Keep logs in `~/Library/Logs` and make the script idempotent.

```nix
launchd.user.agents.nixmc-maintenance = {
  serviceConfig = {
    ProgramArguments = [ "/bin/sh" "-lc" "$HOME/.local/bin/nixmc-maintenance" ];
    StartCalendarInterval = [{ Hour = 9; Minute = 0; }];
    StandardOutPath = "/Users/USER/Library/Logs/nixmc-maintenance.log";
    StandardErrorPath = "/Users/USER/Library/Logs/nixmc-maintenance.log";
  };
};
```

Replace `USER` with the configured primary user and create the script in a
managed location before enabling the agent.
