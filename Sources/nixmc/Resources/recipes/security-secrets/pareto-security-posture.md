---
mcp-verified: 2026-07-15
mcp-query: "darwin: options networking.applicationFirewall and system.defaults.screensaver"
id: pareto-security-posture
title: Pareto Security recommended posture
section: Security & Secrets
symbol: checkmark.shield.fill
summary: Apply Pareto Security's core Mac hardening recommendations without weakening macOS protections.
featured: true
source: https://paretosecurity.com/mac/checks/firewall/
---

Apply the following baseline while preserving any explicit, documented user
exceptions. Pareto Security's Mac checks cover these protections because they
reduce physical-access, network, and malicious-app risk.

## Install the checker

Add the Homebrew casks `pareto-security` and `privileges` to
`.nixmc/homebrew/data.json` so the checker itself is installed and upgraded
with the managed applications. Privileges supports a least-privilege daily
workflow for accounts that are normally standard users. Preserve the existing
cask list; do not replace it with a one-item array.

```json
{
  "casks": ["pareto-security", "privileges"]
}
```

## Use Privileges only with an explicit admin policy

Installing Privileges does not change account membership or grant anyone admin
rights. If the user wants to work day-to-day as a standard user, configure
Privileges through the organization’s documented policy or MDM workflow and
test that an administrator recovery path exists first. Do not remove the
current user from the `admin` group, enable automatic elevation, or put an
administrator credential in this repository as part of this recipe.

## Configure declaratively

Keep the macOS application firewall and stealth mode enabled. Do not set
`blockAllIncoming` unless the user understands the impact on local services.

```nix
networking.applicationFirewall = {
  enable = true;
  enableStealthMode = true;
  blockAllIncoming = false;
};

system.defaults.screensaver = {
  askForPassword = true;
  askForPasswordDelay = 0;
};

# Enable automatic macOS system updates.
system.defaults.SoftwareUpdate.AutomaticallyInstallMacOSUpdates = true;

# Apple security data, critical updates, and App Store updates.
system.defaults.CustomSystemPreferences = {
  "com.apple.SoftwareUpdate" = {
    AutomaticCheckEnabled = true;
    AutomaticDownload = true;
    ConfigDataInstall = true;
    CriticalUpdateInstall = true;
  };
  "com.apple.commerce".AutoUpdate = true;
};

# AirDrop accepts Contacts Only or Off; Pareto Security accepts both values.
system.defaults.CustomUserPreferences."com.apple.sharingd".DiscoverableMode = "Contacts Only";

# Update Homebrew-managed applications when this configuration activates.
homebrew.onActivation = {
  autoUpdate = true;
  upgrade = true;
};
```

Keep the screen-lock idle timeout short: five minutes in a normal workspace and
one minute in a public setting.

## Expected values

Treat these as the values to verify before declaring the posture complete:

| Control | Expected value | Check |
|---|---|---|
| Application firewall | enabled | `/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate` |
| Firewall stealth mode | enabled | `/usr/libexec/ApplicationFirewall/socketfilterfw --getstealthmode` |
| Password after lock | enabled immediately | `askForPassword = true`, `askForPasswordDelay = 0` |
| FileVault | `FileVault is On.` | `fdesetup status` |
| Gatekeeper | `assessments enabled` | `spctl --status` |
| Update checks and downloads | `AutomaticCheckEnabled = true`, `AutomaticDownload = true` | `/Library/Preferences/com.apple.SoftwareUpdate.plist` |
| Critical and security-data updates | `CriticalUpdateInstall = true`, `ConfigDataInstall = true` | `/Library/Preferences/com.apple.SoftwareUpdate.plist` |
| App Store updates | `AutoUpdate = true` | `/Library/Preferences/com.apple.commerce.plist` |
| AirDrop discovery | `DiscoverableMode = "Contacts Only"` or `"Off"` | `com.apple.sharingd` |
| AirPlay Receiver | no `ControlCenter` listener on TCP 5000 or 7000 | `lsof` / System Settings > General > AirDrop & Handoff |
| Remote Login | no listener on TCP 22 | `lsof` / System Settings > General > Sharing |
| Remote Management | no listener on TCP 3283 | `lsof` / System Settings > General > Sharing |
| File and media sharing | no listener on TCP 445 or 3689 | `lsof` / System Settings > General > Sharing |
| Internet Sharing | `NAT.Enabled = 0`, plus disabled primary and AirPort interfaces | `/Library/Preferences/SystemConfiguration/com.apple.nat.plist` |
| Automatic updates | macOS, App Store, and managed apps enabled | System Settings > General > Software Update and App Store settings |

## Verify and guide—do not automate around user consent

- Verify FileVault with `fdesetup status`. If it is off, direct the user to
  **System Settings > Privacy & Security > FileVault**. Enabling it requires an
  interactive recovery-key decision; never store recovery keys in this repo.
- Verify Gatekeeper with `spctl --status`; it should report `assessments
  enabled`. Never globally disable Gatekeeper or strip quarantine attributes.
  For a trusted unsigned app, use the one-time approval path in Finder or
  **System Settings > Privacy & Security**.
- Keep automatic macOS updates enabled with
  `system.defaults.SoftwareUpdate.AutomaticallyInstallMacOSUpdates = true`.
  `ConfigDataInstall` and `CriticalUpdateInstall` cover Apple's security data
  and critical updates; `com.apple.commerce.AutoUpdate` enables App Store
  updates. The last two use supported custom system preferences because this
  nix-darwin version has no typed options for them. `homebrew.onActivation`
  updates managed Homebrew apps whenever the configuration is applied. Explain
  when a restart is required for a security update to take effect.

## Reduce sharing and nearby-device exposure

Set AirDrop to **Contacts Only** or **No One**. Keep AirPlay Receiver, Remote
Login, Remote Management, File Sharing, Media Sharing, Printer Sharing, and
Internet Sharing off unless the user has a current, named need. For each
exception, document its owner, network scope, and removal date.

AirDrop has a verified preference key above. For the listener-based services,
the checker verifies the running state rather than a stable preference key.
Use the System Settings path for those services unless a supported nix-darwin
option is available; do not add an opaque activation script or a guessed
`defaults` key.
