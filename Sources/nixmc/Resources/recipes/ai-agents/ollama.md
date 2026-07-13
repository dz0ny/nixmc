---
id: ai-ollama
title: Ollama + Aider local coding agent
section: AI Agents
symbol: cpu
summary: Run a local coding model through Aider, with Ollama bound to localhost.
featured: true
source: https://nix-community.github.io/home-manager/options/home-manager/services.ollama.html
mcp-verified: 2026-07-14
mcp-query: home-manager options services.ollama.enable services.ollama.host services.ollama.port
---

Run Ollama as a local user service and pull `qwen2.5-coder:7b` for the
**Ollama + Aider** agent in nixmc. Aider supplies the file-editing workflow;
Ollama supplies the local model. It stays bound to localhost.

Make this recipe's changes only in `modules/home/ai-agents.nix`.

```nix
{ pkgs, ... }:
let
  ollama = "${pkgs.ollama}/bin/ollama";
in {
  # The edit-capable harness used by nixmc's Ollama + Aider agent.
  home.packages = [ pkgs.aider-chat ];

  services.ollama = {
    enable = true;
    host = "127.0.0.1";
    port = 11434;
  };

  # Pulls are idempotent. This job runs after login once the Ollama service is ready.
  launchd.agents.ollama-models = {
    enable = true;
    config = {
      Label = "dev.dz0ny.ollama-models";
      RunAtLoad = true;
      ProgramArguments = [
        "/bin/sh"
        "-c"
        ''
          for _ in $(seq 1 60); do
            ${ollama} list >/dev/null 2>&1 && break
            sleep 1
          done
          ${ollama} list >/dev/null 2>&1 || exit 0
          ${ollama} pull qwen2.5-coder:7b
        ''
      ];
    };
  };
}
```

In nixmc, choose **Ollama + Aider** in **Settings > General**, then set the
model tag to `qwen2.5-coder:7b` (or another pulled Ollama coding model).
Aider connects through `ollama_chat/<model>`, the mode recommended by Aider.

## Kimi Code cloud option

For larger coding tasks, choose **Kimi Code + Aider** in **Settings > General**.
It uses Ollama's cloud-backed `kimi-k2.7-code:cloud` model and therefore does
not download model weights locally. Sign in to Ollama first; the model is
cloud-hosted and may use Ollama Cloud allowance or billing.

```sh
ollama pull qwen2.5-coder:7b
```

Pulls are idempotent. Ensure the model fits the Mac's available memory and use
smaller, focused requests for the most reliable local edits.
