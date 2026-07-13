import Foundation

/// A bundled, implementation-oriented configuration recipe. Metadata lives in
/// YAML-like front matter; the Markdown body can include exact Nix, shell, or
/// diff examples for the selected agent to adapt to the user's flake.
struct Recipe: Identifiable, Hashable {
    let id: String
    let title: String
    let section: String
    let symbol: String
    let summary: String
    let featured: Bool
    let source: String?
    /// Optional documentation copied into GUIDE.md after this recipe changes
    /// the configuration and the user applies it.
    let guide: String?
    let body: String

    var agentRequest: String {
        var request = """
        Apply the following nixmc recipe to the current configuration. Treat its
        code as a concrete starting point, but adapt paths, users, package names,
        and existing conventions instead of blindly overwriting files.

        # \(title)

        \(body)
        """
        if let source, !source.isEmpty {
            request += "\n\nSource reference: \(source)"
        }
        if section == "AI Agents" {
            request += """


            Scope boundary: make all configuration changes for this recipe only in
            `modules/home/ai-agents.nix`. Do not edit `flake.nix`, Homebrew data,
            or any other system or Home Manager module. If that file is not
            imported by the current configuration, stop and explain the required
            wiring instead of editing another file.
            """
        }
        return request
    }
}

struct RecipeCategory: Identifiable, Hashable {
    let id: String
    let title: String
    let symbol: String
    let summary: String
    let recipes: [Recipe]
}

enum RecipeSections {
    static let all: [RecipeCategory] = [
        RecipeCategory(id: "My Team", title: "My Team", symbol: "person.3",
                       summary: "Hand-curated recipes shared by your team.", recipes: []),
        RecipeCategory(id: "Packages", title: "Packages", symbol: "shippingbox",
                       summary: "CLI tools and Homebrew applications.", recipes: []),
        RecipeCategory(id: "Fonts", title: "Fonts", symbol: "textformat",
                       summary: "System-wide typefaces for coding, documents, and symbols.", recipes: []),
        RecipeCategory(id: "macOS Settings", title: "macOS Settings", symbol: "slider.horizontal.3",
                       summary: "Declarative Finder, Dock, keyboard, and screenshot defaults.", recipes: []),
        RecipeCategory(id: "Services", title: "Services", symbol: "gearshape.2",
                       summary: "Background services and launchd automation.", recipes: []),
        RecipeCategory(id: "Shell & Environment", title: "Shell & Environment", symbol: "curlybraces",
                       summary: "Shell programs, developer environments, and interactive tooling.", recipes: []),
        RecipeCategory(id: "AI Agents", title: "AI Agents", symbol: "sparkles",
                       summary: "Declarative coding agents, context, and local tool configuration.", recipes: []),
        RecipeCategory(id: "Security & Secrets", title: "Security & Secrets", symbol: "lock.shield",
                       summary: "Authentication, firewall policy, SSH, and secret management.", recipes: []),
        RecipeCategory(id: "For Programmers", title: "For Programmers", symbol: "chevron.left.forwardslash.chevron.right",
                       summary: "Editors, shells, project tooling, Git, containers, and daily development ergonomics.", recipes: []),
        RecipeCategory(id: "For Streamers", title: "For Streamers", symbol: "video",
                       summary: "Recording, streaming, ingest tunnels, capture boxes, and stream-room utilities.", recipes: []),
        RecipeCategory(id: "For Homelab Admins", title: "For Homelab Admins", symbol: "server.rack",
                       summary: "Tunnels, SSH profiles, network tools, local services, and remote access.", recipes: []),
        RecipeCategory(id: "For Security-Minded Users", title: "For Security-Minded Users", symbol: "checkmark.shield",
                       summary: "Touch ID, firewall policy, SSH hygiene, certificates, and encrypted secrets.", recipes: []),
        RecipeCategory(id: "For Designers", title: "For Designers", symbol: "paintpalette",
                       summary: "Creative apps, fonts, screenshots, window management, and visual polish.", recipes: []),
        RecipeCategory(id: "For Writers & Researchers", title: "For Writers & Researchers", symbol: "book",
                       summary: "Notes, citations, PDF workflows, study tools, and low-distraction defaults.", recipes: []),
        RecipeCategory(id: "For Laptop Nomads", title: "For Laptop Nomads", symbol: "airplane",
                       summary: "Travel-safe networking, battery behavior, remote access, and replacement-Mac parity.", recipes: []),
        RecipeCategory(id: "For Gamers", title: "For Gamers", symbol: "gamecontroller",
                       summary: "Game launchers, remote play, Discord, Linux gaming hosts, and controller utilities.", recipes: [])
    ]
}

enum RecipeCatalog {
    private static let bundled = loadBundled()

    @MainActor static var all: [Recipe] {
        (bundled + TeamRecipeStore.shared.recipes)
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    @MainActor static var categories: [RecipeCategory] {
        RecipeSections.all.compactMap { section in
        let recipes = inSection(section.id)
        guard !recipes.isEmpty else { return nil }
        return RecipeCategory(id: section.id, title: section.title, symbol: section.symbol,
                              summary: section.summary, recipes: recipes)
        }
    }

    @MainActor static var featured: [Recipe] { all.filter(\.featured) }

    @MainActor static func inSection(_ section: String) -> [Recipe] {
        all.filter { $0.section == section }
    }

    @MainActor static func search(_ query: String) -> [Recipe] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return [] }
        return all.filter {
            $0.title.lowercased().contains(needle)
                || $0.section.lowercased().contains(needle)
                || $0.summary.lowercased().contains(needle)
                || $0.body.lowercased().contains(needle)
        }
    }

    private static func loadBundled() -> [Recipe] {
        guard let root = Bundle.module.resourceURL,
              let recipes = load(from: root, sectionOverride: nil, idPrefix: "")
        else { return [] }
        return recipes
    }

    static func load(from root: URL, sectionOverride: String?, idPrefix: String) -> [Recipe]? {
        guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            return nil
        }
        return files.compactMap { entry in
            guard let url = entry as? URL, url.pathExtension == "md",
                  let text = try? String(contentsOf: url, encoding: .utf8)
            else { return nil }
            guard let recipe = parse(text, fallbackID: url.deletingPathExtension().lastPathComponent) else {
                return nil
            }
            return Recipe(id: idPrefix + recipe.id, title: recipe.title,
                          section: sectionOverride ?? recipe.section, symbol: recipe.symbol,
                          summary: recipe.summary, featured: recipe.featured, source: recipe.source,
                          guide: recipe.guide, body: recipe.body)
        }
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    static func parse(_ text: String, fallbackID: String) -> Recipe? {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        guard normalized.hasPrefix("---\n"),
              let end = normalized.range(of: "\n---\n", options: [], range: normalized.index(normalized.startIndex, offsetBy: 4)..<normalized.endIndex)
        else { return nil }

        let header = String(normalized[normalized.index(normalized.startIndex, offsetBy: 4)..<end.lowerBound])
        let rawBody = String(normalized[end.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        let guideMarker = "\n## Guide\n"
        let body: String
        let guide: String?
        if let marker = rawBody.range(of: guideMarker) {
            body = String(rawBody[..<marker.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            guide = String(rawBody[marker.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            body = rawBody
            guide = nil
        }
        let values = Dictionary(uniqueKeysWithValues: header.split(separator: "\n").compactMap { line -> (String, String)? in
            guard let colon = line.firstIndex(of: ":") else { return nil }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            return key.isEmpty ? nil : (key, value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'")))
        })

        guard let title = values["title"], let section = values["section"],
              let summary = values["summary"], !body.isEmpty
        else { return nil }
        return Recipe(id: values["id"] ?? fallbackID, title: title, section: section,
                      symbol: values["symbol"] ?? "doc.text", summary: summary,
                      featured: values["featured"] == "true", source: values["source"],
                      guide: guide?.isEmpty == true ? nil : guide, body: body)
    }
}
