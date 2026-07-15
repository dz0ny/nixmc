import Foundation
import CryptoKit

/// Generates a plain-English guide to what a nix-darwin configuration
/// actually does using the coding agent selected in Settings. Generation runs
/// without workspace write access and is cached per provider and config hash.
enum ConfigGuide {
    enum GenerationError: LocalizedError {
        case noConfiguration
        case noAgent
        case agentFailed
        case invalidDocument

        var errorDescription: String? {
            switch self {
            case .noConfiguration:
                "No Nix configuration files were found to document."
            case .noAgent:
                "No selected agent is available to generate the guide."
            case .agentFailed:
                "The selected agent did not return a guide. Check its sign-in and CLI path, then try again."
            case .invalidDocument:
                "The generated guide was missing one or more required sections. Try regenerating it."
            }
        }
    }
    /// Sections the guide is organized under, in order. Kept in lockstep with
    /// the sidebar's Configure areas (`StarterPrompts.areas`) so Help never
    /// drifts from what the rest of the app calls these things.
    static var sectionIDs: [String] { ["Overview"] + StarterPrompts.areas.map(\.id) }

    /// Return a cached guide if one exists for the config's current content.
    static func cached(for content: String) -> String? {
        cached(for: content, agentID: AgentCLI.preferredCacheID)
    }

    /// Generate (or fetch cached) a guide for the configuration at `cwd`.
    static func generate(cwd: URL, homebrewData: URL, force: Bool = false) async -> Result<String, GenerationError> {
        let content = configBundle(repoDir: cwd, homebrewData: homebrewData)
        guard !content.isEmpty else { return .failure(.noConfiguration) }
        guard let agent = AgentCLI.preferredDetected() else { return .failure(.noAgent) }
        if !force, let hit = cached(for: content, agentID: agent.id) {
            if valid(hit) { return .success(hit) }
            // Do not let a malformed response from an older CLI invocation
            // poison every subsequent Help load.
            try? FileManager.default.removeItem(at: cacheURL(content, agentID: agent.id))
        }

        let headings = sectionIDs.map { "## \($0)" }.joined(separator: "\n")
        let instruction = """
        Below are the files of a nix-darwin + Home Manager configuration, \
        included below. Write a user guide to this configuration — the kind \
        of document a new owner of this Mac could actually read to \
        understand how it's set up and how to use it. Describe reality, \
        don't suggest changes or improvements, and don't invent anything \
        not backed by the files.

        Organize it under exactly these top-level headings, in this order, \
        one blank line between sections:

        \(headings)

        Write real prose, not a dry inventory: explain what each area is \
        set up for, how the pieces fit together, and anything a user would \
        actually need to know to use it day to day (a keybinding, a service \
        that needs to be started, a file it reads from, a gotcha). Write \
        for someone skimming, not studying: start each section with a \
        single plain-English sentence summarizing what it covers, then a \
        blank line, then the details. Keep paragraphs to 2-3 sentences — \
        break longer explanations into a bullet list instead of one dense \
        paragraph. Use full markdown freely inside each section — `###` \
        sub-headings to break up a large area, bullet lists for enumerable \
        things, and inline code spans or fenced code blocks for exact \
        package names, commands, or config values — but don't nest lists \
        more than one level deep. Name the real packages, apps, settings, \
        and services you find. For "Overview", write two or three short \
        sentences: what kind of setup this is and for whom it looks \
        tailored. If a section has nothing configured, write exactly \
        "Nothing configured here yet." as its only content. No preamble \
        before the first heading, no closing remarks after the last section. \
        Human-authored recipe guide fragments are appended by NixMC after your \
        output: do not invent, summarize, or reproduce them.
        """
        guard let text = await agent.runReadOnly(instruction: instruction, input: content, cwd: cwd) else {
            return .failure(.agentFailed)
        }
        guard valid(text) else { return .failure(.invalidDocument) }
        try? text.write(to: cacheURL(content, agentID: agent.id), atomically: true, encoding: .utf8)
        return .success(text)
    }

    /// Fast, surgical refresh for the apply pipeline: instead of re-reading and
    /// re-describing the whole config (`generate`), sends just the diff that's
    /// about to be committed plus the guide's current per-section text, and
    /// asks the selected agent to touch only the section(s) the diff affects —
    /// every other section is copied through unchanged. Much smaller input,
    /// much cheaper than a full regenerate on every apply.
    static func update(existing: [String: String], diff: String, cwd: URL) async -> String? {
        guard !diff.isEmpty, diff != "No uncommitted changes." else { return nil }
        guard let agent = AgentCLI.preferredDetected() else { return nil }
        let cacheKey = "diff:" + diff
        if let hit = cached(for: cacheKey, agentID: agent.id) { return hit }

        let headings = sectionIDs.map { "## \($0)" }.joined(separator: "\n")
        let existingText = sectionIDs.map { id in
            "## \(id)\n\(existing[id] ?? "Nothing configured here yet.")"
        }.joined(separator: "\n\n")

        let instruction = """
        Below is a git diff of a nix-darwin + Home Manager \
        configuration (marked DIFF), followed by the current user guide to \
        that configuration (marked GUIDE), organized under these headings, \
        in this order:

        \(headings)

        Update ONLY the section(s) whose content the diff actually changes. \
        Same rules as always: describe reality, name real packages/settings, \
        no suggestions, no invention, "Nothing configured here yet." if a \
        section ends up with nothing. Copy every other section through \
        byte-for-byte unchanged, including its heading. Output the complete \
        guide — every heading listed above, in order — with no preamble and \
        no closing remarks. Human-authored recipe guide fragments are managed \
        separately by NixMC and are not part of this update; do not add or edit \
        them.
        """
        let payload = "DIFF:\n\(diff)\n\nGUIDE:\n\(existingText)"
        guard let text = await agent.runReadOnly(instruction: instruction, input: payload, cwd: cwd) else {
            return nil
        }
        try? text.write(to: cacheURL(cacheKey, agentID: agent.id), atomically: true, encoding: .utf8)
        return text
    }

    /// Split a generated guide into `[sectionID: body]` by its `## ` headings.
    static func sections(from markdown: String) -> [String: String] {
        var out: [String: String] = [:]
        var current: String?
        var body: [String] = []
        func flush() {
            if let id = current {
                out[id] = body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            }
            body = []
        }
        for line in markdown.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("## ") {
                flush()
                current = String(t.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            } else {
                body.append(line)
            }
        }
        flush()
        return out
    }

    static func markdown(from sections: [String: String]) -> String {
        sectionIDs.map { id in
            "## \(id)\n\(sections[id] ?? "Nothing configured here yet.")"
        }.joined(separator: "\n\n") + "\n"
    }

    private static func valid(_ markdown: String) -> Bool {
        let found = sections(from: markdown)
        return sectionIDs.allSatisfy { found[$0] != nil }
    }

    // MARK: - Config content

    /// Concatenate the config files worth summarizing: nix modules and the
    /// Homebrew JSON. Deterministic order (sorted paths) so the content hash
    /// — and therefore the cache — is stable across runs.
    private static func configBundle(repoDir: URL, homebrewData: URL) -> String {
        var files: [(String, String)] = []
        let ignoredDirectories: Set<String> = [".git", ".direnv", "result", ".nixmc"]
        if let items = FileManager.default.enumerator(at: repoDir, includingPropertiesForKeys: [.isDirectoryKey]) {
            for case let url as URL in items {
                if ignoredDirectories.contains(url.lastPathComponent) {
                    items.skipDescendants()
                    continue
                }
                guard url.pathExtension == "nix",
                      let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
                files.append((url.path(percentEncoded: false).replacingOccurrences(of: repoDir.path(percentEncoded: false), with: ""), text))
            }
        }
        if let hb = try? String(contentsOf: homebrewData, encoding: .utf8) {
            files.append((".nixmc/homebrew/data.json", hb))
        }
        files.sort { $0.0 < $1.0 }
        return files.map { "### \($0.0)\n```\n\($0.1)\n```\n" }.joined(separator: "\n")
    }

    // MARK: - Cache

    private static func cached(for content: String, agentID: String) -> String? {
        try? String(contentsOf: cacheURL(content, agentID: agentID), encoding: .utf8)
    }

    /// On-disk cache path for a guide, namespaced by selected provider.
    private static func cacheURL(_ content: String, agentID: String) -> URL {
        let digest = SHA256.hash(data: Data(content.utf8))
            .map { String(format: "%02x", $0) }.joined()
        let dir = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("nixmc/guide/\(agentID)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(digest).txt")
    }
}
