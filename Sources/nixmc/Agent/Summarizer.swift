import Foundation
import CryptoKit

/// Turns a git diff into short generated content using the coding agent selected
/// in Settings. Requests run without workspace write access and are cached per
/// provider, so switching agents never reuses the other agent's response.
enum Summarizer {
    private static let commitCacheKind = "commits-v2"

    /// Return a cached summary if one exists for this exact diff.
    static func cached(for diff: String) -> String? {
        cached(for: diff, kind: "summaries", agentID: AgentCLI.preferredCacheID)
    }

    /// Generate (or fetch cached) a summary for `diff`.
    static func summarize(_ diff: String, cwd: URL, force: Bool = false) async -> String? {
        guard let agent = AgentCLI.preferredDetected() else { return nil }
        if !force, let hit = cached(for: diff, kind: "summaries", agentID: agent.id) { return hit }

        let instruction = """
        You are reviewing a git diff of a nix-darwin configuration, piped on stdin.
        In 2-5 short bullet points, describe in plain English what changed and why \
        it matters (packages, services, settings, files). Be concise and concrete. \
        No code blocks, no preamble — just the bullets.
        """
        guard let text = await agent.runReadOnly(instruction: instruction, input: diff, cwd: cwd) else {
            return nil
        }
        try? text.write(to: cacheURL("summaries", diff, agentID: agent.id),
                        atomically: true, encoding: .utf8)
        return text
    }

    /// Write a one-line commit message for `diff` using the selected agent.
    static func commitMessage(for diff: String, cwd: URL) async -> String? {
        guard let agent = AgentCLI.preferredDetected() else { return nil }
        if let hit = cached(for: diff, kind: commitCacheKind, agentID: agent.id) {
            return hit
        }
        let instruction = """
        You are given a git diff of a nix-darwin configuration on stdin. Write \
        exactly one concise Git commit subject for the principal change.

        Requirements:
        - Imperative mood, at most 50 characters.
        - Name the concrete configuration change, not the user's request or its \
          conversational wording.
        - Do not list every changed item, explain rationale, use a period, or add \
          a prefix such as "feat:" or "commit:".
        - Prefer a precise subject such as "Add Fira Code and Hack fonts" over a \
          sentence describing the work.

        Output only the subject, with no quotes or preamble.
        """
        guard let output = await agent.runReadOnly(instruction: instruction, input: diff, cwd: cwd) else {
            return nil
        }
        let raw = output
            .components(separatedBy: .newlines).first?
            .trimmingCharacters(in: .whitespaces) ?? ""
        let msg = conciseSubject(raw)
        guard !msg.isEmpty else { return nil }
        try? msg.write(to: cacheURL(commitCacheKind, diff, agentID: agent.id),
                        atomically: true, encoding: .utf8)
        return msg
    }

    /// Defend the Git history against an overlong provider response even when
    /// the provider ignores the prompt. Cut at a word boundary, not mid-word.
    private static func conciseSubject(_ subject: String, limit: Int = 50) -> String {
        let cleaned = subject
            .replacingOccurrences(of: "\"", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count > limit else { return cleaned }

        let prefix = String(cleaned.prefix(limit + 1))
        guard let boundary = prefix.lastIndex(where: { $0.isWhitespace }) else {
            return String(cleaned.prefix(limit))
        }
        return String(prefix[..<boundary]).trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Cache

    private static func cached(for diff: String, kind: String, agentID: String) -> String? {
        try? String(contentsOf: cacheURL(kind, diff, agentID: agentID), encoding: .utf8)
    }

    /// Cache generated content under a provider-specific directory.
    private static func cacheURL(_ kind: String, _ diff: String, agentID: String) -> URL {
        let digest = SHA256.hash(data: Data(diff.utf8))
            .map { String(format: "%02x", $0) }.joined()
        let dir = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("nixmc/\(kind)/\(agentID)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(digest).txt")
    }
}
