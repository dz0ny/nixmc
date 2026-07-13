import Foundation

/// One entry from Homebrew's public install-count analytics
/// (https://formulae.brew.sh/api/analytics), used to surface a "Popular"
/// section in the packages picker so users can add well-known apps/tools
/// without knowing the exact formula name up front.
struct PopularPackage: Identifiable, Equatable {
    let name: String
    let kind: PackageKind
    let count: Int
    var id: String { "\(kind)/\(name)" }
}

enum PackageKind { case app, cli }

enum HomebrewPopular {
    private static let caskURL = URL(string: "https://formulae.brew.sh/api/analytics/cask-install/30d.json")!
    private static let brewURL = URL(string: "https://formulae.brew.sh/api/analytics/install-on-request/30d.json")!

    /// Top `limit` casks and top `limit` brews by 30-day install count,
    /// fetched fresh on every call — the caller decides how to cache.
    static func fetch(limit: Int = 20) async throws -> [PopularPackage] {
        async let casks = fetchList(caskURL, kind: .app)
        async let brews = fetchList(brewURL, kind: .cli)
        let (c, b) = try await (casks, brews)
        return Array(c.prefix(limit)) + Array(b.prefix(limit))
    }

    private struct Item: Decodable {
        let cask: String?
        let formula: String?
        let count: String
    }
    private struct Response: Decodable { let items: [Item] }

    private static func fetchList(_ url: URL, kind: PackageKind) async throws -> [PopularPackage] {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw NixmcError.command("Couldn't reach formulae.brew.sh")
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return decoded.items.compactMap { item in
            guard let name = item.cask ?? item.formula else { return nil }
            let count = Int(item.count.replacingOccurrences(of: ",", with: "")) ?? 0
            return PopularPackage(name: name, kind: kind, count: count)
        }
    }
}
