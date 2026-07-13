---
mcp-verified: manual
mcp-query: not-applicable
id: home-manager-apps
title: Manage user applications safely
section: Security & Secrets
symbol: app.badge.checkmark
summary: Keep Home Manager application copies in the user domain instead of modifying protected app bundles.
featured: false
source: https://github.com/nix-community/home-manager/issues/8067
---

When a Home Manager application-copy permission check fails, do not recursively
`chmod` an app bundle in `/Applications`. Keep managed user applications under
the user's home directory and grant the terminal or nixmc Full Disk Access only
when macOS explicitly requires it.

```nix
targets.darwin.copyApps.enable = true;
```

If the current Home Manager version exposes a compatibility issue, inspect the
exact activation error first. Prefer a targeted configuration change or upgrade
over broad permission changes to framework symlinks.
