import Foundation

/// An external coding-agent CLI that edits files in a directory given a prompt.
/// nixmc delegates all "edit the config" work to one of these — it never calls
/// an LLM API itself.
struct AgentCLI: Identifiable, Hashable {
    let id: String            // the binary name, e.g. "claude"
    let displayName: String
    /// Argument vector; the prompt is appended as the final argument.
    let launchArgs: [String]
    /// How to interpret the CLI's stdout for live progress.
    let format: OutputFormat

    enum OutputFormat: Hashable { case plainText, claudeStreamJSON }

    private static let codexExecutable = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".local/bin/codex").path

    /// Known agents we know how to drive in non-interactive mode.
    ///
    /// claude streams NDJSON events (parsed for live progress) and skips its
    /// interactive permission prompts so it can inspect the system and edit the
    /// flake headlessly — the app's whole purpose is autonomous config editing.
    static let known: [AgentCLI] = [
        AgentCLI(id: "claude", displayName: "Claude Code",
                 launchArgs: ["claude", "-p", "--output-format", "stream-json",
                              "--verbose", "--dangerously-skip-permissions"],
                 format: .claudeStreamJSON),
        AgentCLI(id: "codex", displayName: "Codex CLI",
                 // MCP-NixOS runs `nix` as a local stdio server. Codex's
                 // workspace sandbox cancels that nested tool process in a
                 // non-interactive run, so use the same autonomous mode as
                 // Claude for an agent session explicitly approved by nixmc.
                 launchArgs: [codexExecutable, "exec", "--dangerously-bypass-approvals-and-sandbox"], format: .plainText),
        AgentCLI(id: "aider", displayName: "Aider",
                 launchArgs: ["aider", "--yes", "--message"], format: .plainText),
        AgentCLI(id: "ollama-aider", displayName: "Ollama + Aider",
                 launchArgs: ["aider"], format: .plainText),
        AgentCLI(id: "kimi-aider", displayName: "Kimi Code + Aider",
                 launchArgs: ["aider"], format: .plainText),
    ]

    /// The subset of known agents actually installed on this machine.
    static func detected() -> [AgentCLI] {
        known.filter { agent in
            guard let executable = agent.launchArgs.first else { return false }
            if executable.hasPrefix("/") {
                return FileManager.default.isExecutableFile(atPath: executable)
            }
            return Shell.which(executable) != nil
        }
    }

    /// The installed agent selected in Settings. AppState persists its initial
    /// fallback during refresh, so background tasks resolve the same provider.
    static func preferredDetected() -> AgentCLI? {
        let available = detected().filter {
            $0.id == "claude" || $0.id == "codex" || $0.id == "ollama-aider" || $0.id == "kimi-aider"
        }
        let preferredID = UserDefaults.standard.string(forKey: "preferredAgent") ?? ""
        return available.first { $0.id == preferredID } ?? available.first
    }

    /// Namespace generated-content caches by provider so changing agents does
    /// not display content produced by the previous selection.
    static var preferredCacheID: String {
        let id = UserDefaults.standard.string(forKey: "preferredAgent") ?? ""
        return id.isEmpty ? "automatic" : id
    }

    /// Run the agent in `cwd` with `prompt`, streaming readable progress lines.
    func run(prompt: String, cwd: URL, onSpawn: ((Int32) -> Void)? = nil,
             onLine: @escaping (String) -> Void) async -> Bool {
        let mcpConfig = mcpConfigFile()
        defer {
            if let mcpConfig { try? FileManager.default.removeItem(at: mcpConfig) }
        }
        let cmd = shellCommand(agentArguments(prompt: prompt, mcpConfig: mcpConfig))
        let format = self.format
        let code = await Shell.streamLogin(cmd, cwd: cwd, onSpawn: onSpawn) { raw in
            switch format {
            case .plainText:
                onLine(raw)
            case .claudeStreamJSON:
                for line in ClaudeStream.lines(from: raw) { onLine(line) }
            }
        }
        return code == 0
    }

    /// The nixos MCP server is attached only to nixmc-launched agent sessions.
    /// It is intentionally not registered in the user's global Claude/Codex
    /// config, where it would affect unrelated projects.
    private func agentArguments(prompt: String, mcpConfig: URL?) -> [String] {
        switch id {
        case "claude":
            guard let mcpConfig else { return launchArgs + [prompt] }
            // `--mcp-config` accepts one or more paths, so `--` is required
            // before the positional prompt to stop it consuming that prompt.
            return launchArgs + ["--mcp-config", mcpConfig.path, "--", prompt]
        case "codex":
            return launchArgs + [
                "-c", "mcp_servers.nixos.command=\"nix\"",
                "-c", "mcp_servers.nixos.args=[\"run\",\"github:utensils/mcp-nixos\",\"--\"]",
                prompt,
            ]
        case "ollama-aider":
            let model = UserDefaults.standard.string(forKey: "ollamaAiderModel") ?? "qwen2.5-coder:7b"
            return ["aider", "--yes", "--no-auto-commits", "--model", "ollama_chat/\(model)", "--message", prompt]
        case "kimi-aider":
            return ["aider", "--yes", "--no-auto-commits", "--model", "ollama_chat/kimi-k2.7-code:cloud", "--message", prompt]
        default:
            return launchArgs + [prompt]
        }
    }

    private func mcpConfigFile() -> URL? {
        guard id == "claude" else { return nil }
        let config: [String: Any] = [
            "mcpServers": [
                "nixos": [
                    "command": "nix",
                    "args": ["run", "github:utensils/mcp-nixos", "--"],
                ],
            ],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: config, options: [.sortedKeys]) else {
            return nil
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nixmc-mcp-nixos-\(UUID().uuidString).json")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    /// Run a generation-only request without allowing workspace writes.
    /// Claude can disable tools entirely; Codex runs in its read-only sandbox
    /// and writes only its final answer to a temporary output file.
    func runReadOnly(instruction: String, input: String, cwd: URL) async -> String? {
        // `claude -p` treats piped stdin as the user prompt, overriding its
        // positional prompt. Keep all context in the explicit prompt so both
        // CLIs receive the instruction and the supplied configuration.
        let prompt = """
        \(instruction)

        <nixmc-input>
        \(input)
        </nixmc-input>
        """
        switch id {
        case "claude":
            let args = [launchArgs[0], "-p", "--output-format", "text",
                        "--no-session-persistence", "--tools", "", "--", prompt]
            var output = ""
            let code = await Shell.streamLogin(shellCommand(args), cwd: cwd) {
                output += $0 + "\n"
            }
            let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return code == 0 && !text.isEmpty ? text : nil

        case "codex":
            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("nixmc-codex-\(UUID().uuidString).txt")
            defer { try? FileManager.default.removeItem(at: outputURL) }
            let args = [launchArgs[0], "exec", "--sandbox", "read-only", "--ephemeral",
                        "--color", "never", "--output-last-message", outputURL.path,
                        prompt]
            let code = await Shell.streamLogin(shellCommand(args), cwd: cwd) { _ in }
            guard code == 0,
                  let output = try? String(contentsOf: outputURL, encoding: .utf8) else { return nil }
            let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text

        default:
            return nil
        }
    }

    private func shellCommand(_ args: [String]) -> String {
        args.map { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }
            .joined(separator: " ")
    }
}
