import Foundation

/// Codable view of `.nixmc/homebrew/data.json`. Brew edits are pure JSON —
/// no Nix parsing, no AST, no Rust.
struct HomebrewData: Codable {
    var taps: [String] = []
    var brews: [String] = []
    var casks: [String] = []
    var onActivation: OnActivation?

    struct OnActivation: Codable {
        var autoUpdate: Bool?
        var upgrade: Bool?
        var cleanup: String?
    }

    init() {}

    /// Tolerant decode: any missing list key becomes `[]` rather than throwing,
    /// so partial `data.json` files (e.g. brews-only) load cleanly.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        taps = try c.decodeIfPresent([String].self, forKey: .taps) ?? []
        brews = try c.decodeIfPresent([String].self, forKey: .brews) ?? []
        casks = try c.decodeIfPresent([String].self, forKey: .casks) ?? []
        onActivation = try c.decodeIfPresent(OnActivation.self, forKey: .onActivation)
    }

    static func load(from url: URL) throws -> HomebrewData {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(HomebrewData.self, from: data)
    }

    func save(to url: URL) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(self).write(to: url)
    }

    mutating func addCask(_ name: String) { if !casks.contains(name) { casks.append(name) } }
    mutating func removeCask(_ name: String) { casks.removeAll { $0 == name } }
    mutating func addBrew(_ name: String) { if !brews.contains(name) { brews.append(name) } }
    mutating func removeBrew(_ name: String) { brews.removeAll { $0 == name } }
}
