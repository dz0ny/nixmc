---
mcp-verified: manual
mcp-query: not-applicable
id: actual-budget
title: Host Actual Budget locally
section: Services
symbol: banknote
summary: Run the Actual Budget sync server at login, storing encrypted budget data on this Mac.
featured: false
source: https://actualbudget.org/docs/config/
---

Install `pkgs.actual-server` and run it as a user launch agent. Keep it bound
to `127.0.0.1` by default, persist its data under Application Support, and log
to `~/Library/Logs`. Add this only to the Darwin services module:

```nix
environment.systemPackages = [ pkgs.actual-server ];

launchd.user.agents.actual-budget = {
  serviceConfig = {
    ProgramArguments = [ "${pkgs.actual-server}/bin/actual-server" ];
    EnvironmentVariables = {
      ACTUAL_DATA_DIR = "/Users/USER/Library/Application Support/Actual";
      ACTUAL_HOSTNAME = "127.0.0.1";
      ACTUAL_PORT = "5006";
    };
    RunAtLoad = true;
    KeepAlive = true;
    StandardOutPath = "/Users/USER/Library/Logs/actual-budget.log";
    StandardErrorPath = "/Users/USER/Library/Logs/actual-budget.log";
  };
};
```

After applying, open `http://127.0.0.1:5006` and set the server password.
Do not store that password in the flake. If remote access is needed, put a
TLS-terminating reverse proxy or a private network such as Tailscale in front
of it; do not change the default bind address to expose it publicly.
