---
mcp-verified: manual
mcp-query: not-applicable
id: package-release-age
title: Delay new package releases
section: Security & Secrets
symbol: clock.badge.checkmark
summary: Avoid installing freshly published npm, Bun, Python, and uv packages.
featured: false
source: https://github.com/zupo/dotfiles/blob/main/common/files.nix
---

Configure package managers to avoid packages published during a configurable
cooling-off period. Use a seven-day default, but preserve existing user package
manager settings and do not overwrite credentials, registries, or proxies.

```nix
{ ... }:
{
  home.file.".npmrc".text = ''
    min-release-age=7
    minimum-release-age=10080
    save-exact=true
  '';

  home.file.".bunfig.toml".text = ''
    [install]
    minimumReleaseAge = 604800
  '';

  home.file.".config/uv/uv.toml".text = ''
    exclude-newer = "7 days"
  '';

  home.file.".config/pip/pip.conf".text = ''
    [install]
    uploaded-prior-to = P7D
  '';
}
```

## Guide

Newly published packages are a higher supply-chain risk because malicious or
compromised releases are often detected shortly after publication. These
settings delay automatic adoption while leaving explicit upgrades under the
user's control. Review any existing package-manager configuration before
merging so custom indexes and credentials remain intact.
