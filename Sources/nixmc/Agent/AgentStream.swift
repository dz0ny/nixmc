import Foundation

/// Turns Claude Code's `--output-format stream-json` NDJSON events into short,
/// human-readable progress lines. Without this, `claude -p` (plain text) emits
/// nothing until the run finishes, so the UI looks stuck.
enum ClaudeStream {
    /// Parse one NDJSON line; return display lines (may be empty for noise).
    static func lines(from raw: String) -> [String] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"),
              let data = trimmed.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String
        else {
            // Not JSON (e.g. a stray log line) — surface it as-is if non-empty.
            return trimmed.isEmpty ? [] : [trimmed]
        }

        switch type {
        case "assistant":
            return assistantLines(obj)
        case "user":
            return userLines(obj)
        case "result":
            if let isErr = obj["is_error"] as? Bool, isErr,
               let r = obj["result"] as? String { return ["⚠︎ \(r)"] }
            return []
        default:
            return []   // system / rate_limit_event / stream_event → ignore
        }
    }

    private static func content(_ obj: [String: Any]) -> [[String: Any]] {
        (obj["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
    }

    private static func assistantLines(_ obj: [String: Any]) -> [String] {
        var out: [String] = []
        for item in content(obj) {
            switch item["type"] as? String {
            case "text":
                if let t = (item["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !t.isEmpty { out.append(t) }
            case "tool_use":
                let name = item["name"] as? String ?? "tool"
                let input = item["input"] as? [String: Any] ?? [:]
                out.append("› \(name)\(summary(name, input))")
            default:
                break   // skip thinking / redacted
            }
        }
        return out
    }

    private static func userLines(_ obj: [String: Any]) -> [String] {
        for item in content(obj) where item["type"] as? String == "tool_result" {
            if let isErr = item["is_error"] as? Bool, isErr {
                let msg = (item["content"] as? String) ?? "tool error"
                return ["  ✗ \(firstLine(msg))"]
            }
        }
        return []   // successful results are noise; the next assistant turn speaks
    }

    /// A compact one-line summary of a tool call's most relevant argument.
    private static func summary(_ name: String, _ input: [String: Any]) -> String {
        if let path = (input["file_path"] as? String) ?? (input["path"] as? String) {
            return "  " + shortPath(path)
        }
        if let cmd = input["command"] as? String {
            return "  " + firstLine(cmd)
        }
        if let pattern = (input["pattern"] as? String) ?? (input["query"] as? String) {
            return "  \(pattern)"
        }
        return ""
    }

    private static func shortPath(_ p: String) -> String {
        let parts = p.split(separator: "/")
        return parts.suffix(2).joined(separator: "/")
    }
    private static func firstLine(_ s: String) -> String {
        let line = s.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? s
        return line.count > 100 ? String(line.prefix(100)) + "…" : line
    }
}
