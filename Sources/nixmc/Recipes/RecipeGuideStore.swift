import Foundation

/// Stores human-authored recipe guide fragments outside Git, then combines them
/// with the generated configuration guide. The final `GUIDE.md` is tracked;
/// the raw fragments stay local so recipe documentation can be reassembled
/// after a guide refresh without asking an agent to rewrite it.
enum RecipeGuideStore {
    private static let directoryName = ".nixmc/recipe-guides"
    private static let ignoreEntry = ".nixmc/recipe-guides/"
    private static let startPrefix = "<!-- nixmc:recipe-guide "
    private static let endMarker = "<!-- /nixmc:recipe-guide -->"

    private struct Index: Codable {
        var entries: [Entry] = []
    }

    private struct Entry: Codable {
        let id: String
        let section: String
        let filename: String
    }

    /// Copy the Markdown after a recipe's `## Guide` marker exactly as supplied.
    /// The file is ignored by Git; only the assembled GUIDE.md is committed.
    static func store(_ recipe: Recipe, in repoDir: URL) throws {
        guard let guide = recipe.guide, !guide.isEmpty else { return }
        try ensureIgnored(in: repoDir)

        let directory = repoDir.appending(path: directoryName, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let filename = safeFilename(for: recipe.id) + ".md"
        try guide.write(to: directory.appending(path: filename), atomically: true, encoding: .utf8)

        let indexURL = directory.appending(path: "index.json")
        var index = loadIndex(at: indexURL)
        index.entries.removeAll { $0.id == recipe.id }
        index.entries.append(Entry(id: recipe.id, section: recipe.section, filename: filename))
        index.entries.sort { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(index).write(to: indexURL)
    }

    /// Remove previously assembled human guide blocks before asking an agent to
    /// refresh the machine-generated guide. The fragments must remain verbatim.
    static func removingBlocks(from sections: [String: String]) -> [String: String] {
        var cleaned = sections
        for (section, text) in cleaned {
            cleaned[section] = removingBlocks(from: text)
        }
        return cleaned
    }

    /// Append all locally stored human guide fragments to their intended guide
    /// sections. The fragment text itself is never generated, summarized, or
    /// otherwise changed by NixMC.
    static func combining(_ sections: [String: String], in repoDir: URL) -> [String: String] {
        var combined = removingBlocks(from: sections)
        let directory = repoDir.appending(path: directoryName, directoryHint: .isDirectory)
        let index = loadIndex(at: directory.appending(path: "index.json"))

        for entry in index.entries {
            guard let guide = try? String(contentsOf: directory.appending(path: entry.filename), encoding: .utf8),
                  !guide.isEmpty else { continue }
            let section = ConfigGuide.sectionIDs.contains(entry.section) ? entry.section : "Overview"
            let block = "\(startPrefix)\(entry.id) -->\n\(guide)\n\(endMarker)"
            let current = combined[section] ?? "Nothing configured here yet."
            combined[section] = current == "Nothing configured here yet."
                ? block
                : current + "\n\n" + block
        }
        return combined
    }

    private static func loadIndex(at url: URL) -> Index {
        guard let data = try? Data(contentsOf: url),
              let index = try? JSONDecoder().decode(Index.self, from: data)
        else { return Index() }
        return index
    }

    private static func safeFilename(for id: String) -> String {
        let safe = id.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_" ? Character(String(scalar)) : "_"
        }
        return safe.isEmpty ? "recipe-guide" : String(safe)
    }

    private static func ensureIgnored(in repoDir: URL) throws {
        let url = repoDir.appending(path: ".gitignore")
        var text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let entries = Set(text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) })
        guard !entries.contains(ignoreEntry) else { return }
        if !text.isEmpty, !text.hasSuffix("\n") { text += "\n" }
        text += "\(ignoreEntry)\n"
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func removingBlocks(from text: String) -> String {
        var result = text
        while let start = result.range(of: startPrefix),
              let end = result.range(of: endMarker, range: start.upperBound..<result.endIndex) {
            result.removeSubrange(start.lowerBound..<end.upperBound)
        }
        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Nothing configured here yet." : trimmed
    }
}
