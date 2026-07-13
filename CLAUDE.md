# CLAUDE.md

Guidance for working in this repo. See `README.md` for the user-facing overview.

## What this is

**nixmc** — a native macOS/SwiftUI menu-bar app that puts a coding-agent CLI in
front of a nix-darwin configuration. The user describes a change in plain English;
a configured agent (`claude`/`codex`/`aider`) edits the flake, the app validates
with `darwin-rebuild build`, applies with `switch`, and commits to git for rollback.

**The app is an orchestrator, not a Nix tool.** No Rust, no LLM SDK, no Nix AST
parser. It shells out to `nix`, `darwin-rebuild`, `git`, and the agent CLI. Brew
changes are plain JSON writes consumed by the flake via `builtins.fromJSON`.

## Build & run

```bash
swift build            # compile
make dev               # swift run — fast, no bundle (dev loop)
make run               # build dist/nixmc.app and open it
make app               # build the .app bundle only
make sign / dmg / notarize / release   # packaging (see Makefile header)
```

Requires macOS 14+ and Swift 5.9. A single SwiftPM executable target `nixmc`
at `Sources/nixmc`.

## Layout

```
Sources/nixmc/
├─ App.swift                # MenuBarExtra + window entry point
├─ Bootstrap/              # first-run: install Nix, symlink /etc/nix-darwin, scaffold flake
├─ Agent/                  # detect + drive the agent CLI, stream/summarize replies
├─ Config/                 # DarwinRebuild (build/switch), HomebrewData (JSON), NixFormat
├─ History/Git.swift       # commit / log / revert
├─ Privileged/AdminShell   # osascript "with administrator privileges"
├─ Settings/               # AppSettings (all tunables) + Settings window (⌘,) UI
├─ Support/{Shell,Paths}   # Process wrapper + path/PATH resolution
├─ Updates/                # background flake-update checks + parked proposals
└─ UI/                     # AppState (view model) + SwiftUI screens
```

## Key facts & conventions

- **Everything external runs through a login shell.** A Finder-launched menu-bar
  app inherits a minimal PATH, so `nix`, `darwin-rebuild`, `git`, and agent CLIs
  are invoked via `zsh -lc` (see `Support/Shell.swift`). Don't assume tools are on
  a bare PATH.
- **Two PATHs to the config.** The repo (git + flake) is user-writable; prefer an
  existing `/etc/nix-darwin` (symlink resolved), else fall back to
  `~/.config/nixmc/darwin`. Resolve via `Paths.repoDir` — never hardcode.
- **Privileged actions are prompt-once.** Admin work (Nix install, the canonical
  symlink) goes through `AdminShell` / osascript. Editing and committing the flake
  needs no admin.
- **Homebrew is data, not Nix.** Brew add/remove writes `.nixmc/homebrew/data.json`
  (`Config/HomebrewData.swift`); the flake reads it with `builtins.fromJSON`. Don't
  edit Nix for brew changes.
- **Git off the main actor.** Committing runs off the main thread so the UI doesn't
  freeze; the app never gpg-signs its internal commits.
- **Settings are UserDefaults-backed.** Every tunable lives in `AppSettings`
  (`Settings/AppSettings.swift`) with registered defaults; behavior code reads it
  at the moment of use, so changes need no relaunch. Accent palettes live in
  `UI/Theme.swift` — the window remounts on theme change (`.id(settings.themeID)`)
  because `Theme.*` lookups are static, not observed.
- **Errors** use `NixmcError` (`Support/Shell.swift`) with `LocalizedError`.

## After changes

Run `swift build` (or `make dev`) to confirm it compiles. There is no test suite;
verify behavior by driving the app.
