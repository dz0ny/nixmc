---
mcp-verified: manual
mcp-query: not-applicable
id: zsh-basics
title: Configure an ergonomic Zsh shell
section: Shell & Environment
symbol: terminal
summary: Enable Zsh, useful completion, a shared history, and modern navigation tools.
featured: false
source: https://github.com/nix-community/home-manager
---

Use Home Manager program modules instead of putting configuration into
unmanaged dotfiles.

```nix
programs.zsh = {
  enable = true;
  enableCompletion = true;
  autosuggestion.enable = true;
  syntaxHighlighting.enable = true;
  history = {
    save = 10000;
    size = 10000;
    ignoreDups = true;
    share = true;
  };
};

programs.zoxide.enable = true;
programs.fzf.enable = true;
```

Keep any existing aliases and custom shell hooks unless they conflict with this
configuration.
