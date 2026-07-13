---
mcp-verified: 2026-07-13
mcp-query: "darwin: option security.pam.services.sudo_local.touchIdAuth"
id: touch-id-sudo
title: Enable Touch ID for sudo
section: Security & Secrets
symbol: touchid
summary: Add the supported PAM rule for Touch ID authentication in Terminal.
featured: true
source: https://github.com/nix-darwin/nix-darwin/blob/master/modules/security/pam.nix
---

Enable the nix-darwin option in the system module. This is a local convenience
setting, not a replacement for the password fallback.

```nix
security.pam.services.sudo_local.touchIdAuth = true;
```

Do not edit `/etc/pam.d/sudo` imperatively; nix-darwin owns the generated PAM
configuration and will preserve it across rebuilds.
