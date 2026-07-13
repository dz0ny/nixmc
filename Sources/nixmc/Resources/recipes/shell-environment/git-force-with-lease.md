---
mcp-verified: manual
mcp-query: not-applicable
id: git-force-with-lease
title: Safer Git force pushes
section: Shell & Environment
symbol: arrow.triangle.2.circlepath
summary: Rewrite force pushes to use force-with-lease protection.
featured: false
source: https://github.com/zupo/dotfiles/blob/main/common/zsh.nix
---

Add a Zsh wrapper that changes `git push -f` and `git push --force` into
`git push --force-with-lease`. Leave every other Git command and argument
unchanged, and do not introduce aliases that shadow other commands.

```nix
{ ... }:
{
  programs.zsh.initContent = ''
    git() {
      if [[ "$1" == "push" ]]; then
        local args=("push")
        shift
        for arg in "$@"; do
          case "$arg" in
            -f|--force) args+=("--force-with-lease") ;;
            *) args+=("$arg") ;;
          esac
        done
        command git "''${args[@]}"
      else
        command git "$@"
      fi
    }
  '';
}
```

## Guide

`--force-with-lease` refuses to overwrite a remote branch if it has changed
since the last fetch. It retains the intended history-rewrite workflow while
protecting teammates' commits. Fetch before force-pushing and use an explicit
lease only when you have verified the remote branch state.
