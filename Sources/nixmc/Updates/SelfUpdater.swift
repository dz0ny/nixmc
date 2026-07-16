import AppKit
import Foundation

/// Self-update from GitHub Releases, modeled on Pareto Security's updater
/// (no Sparkle): fetch the release list, pick the newest version with a
/// zipped .app asset, download it, verify the downloaded bundle is signed
/// by the same Developer ID as the running one, swap the bundle in place
/// with `ditto`, and relaunch.
enum SelfUpdater {
    static let repo = "dz0ny/nixmc"

    struct Release: Decodable {
        let tagName: String
        let htmlUrl: String
        let prerelease: Bool
        let draft: Bool
        let assets: [Asset]

        /// "v1.2.3" / "1.2.3" → [1, 2, 3]; non-numeric tags → [].
        var version: [Int] { parseVersion(tagName) }
        var appAsset: Asset? { assets.first { $0.name.hasSuffix(".app.zip") } }
    }

    struct Asset: Decodable {
        let name: String
        let browserDownloadUrl: URL
        let size: Int
    }

    enum UpdateError: LocalizedError {
        case notBundled
        case badDownload(String)
        case signatureMismatch(installed: String, downloaded: String)

        var errorDescription: String? {
            switch self {
            case .notBundled:
                return "Self-update needs the installed nixmc.app (not a dev build)."
            case .badDownload(let why):
                return "Update download failed: \(why)"
            case .signatureMismatch(let installed, let downloaded):
                return "Update rejected: signing identity \"\(downloaded)\" "
                    + "does not match the installed app (\"\(installed)\")."
            }
        }
    }

    /// [1, 2, 3]-style version of the running app; [] when unbundled (dev run).
    static var currentVersion: [Int] {
        parseVersion(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
    }

    /// True when running from a real .app bundle (self-update is possible).
    static var isBundled: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    /// Newest published release that is newer than the running app and ships
    /// a zipped .app; nil when up to date (or unbundled).
    static func check() async throws -> Release? {
        let current = currentVersion
        guard isBundled, !current.isEmpty else { return nil }
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases?per_page=10")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, _) = try await URLSession.shared.data(for: request)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let releases = try decoder.decode([Release].self, from: data)
        return releases
            .filter { !$0.draft && !$0.prerelease && $0.appAsset != nil }
            .filter { isNewer($0.version, than: current) }
            .max { isNewer($1.version, than: $0.version) }
    }

    /// Download, verify, install over the running bundle, and relaunch.
    /// Escalates via the admin prompt when the install location isn't
    /// user-writable. Does not return on success — the app terminates.
    static func installAndRelaunch(_ release: Release) async throws {
        guard isBundled else { throw UpdateError.notBundled }
        guard let asset = release.appAsset else {
            throw UpdateError.badDownload("release has no .app.zip asset")
        }

        let (zipUrl, response) = try await URLSession.shared.download(from: asset.browserDownloadUrl)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw UpdateError.badDownload("unexpected HTTP status")
        }
        let zipSize = (try? zipUrl.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard zipSize == asset.size else {
            throw UpdateError.badDownload("size mismatch (\(zipSize) of \(asset.size) bytes)")
        }

        let staging = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("nixmc-update-\(release.tagName)")
        try? FileManager.default.removeItem(at: staging)
        // ditto preserves code signatures and resource forks that a plain
        // unzip can drop, which would break the Gatekeeper seal.
        let unzip = try Shell.run("/usr/bin/ditto", ["-xk", zipUrl.path, staging.path])
        guard unzip.ok else { throw UpdateError.badDownload(unzip.stderr) }
        guard let downloaded = try FileManager.default
            .contentsOfDirectory(at: staging, includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension == "app" }) else {
            throw UpdateError.badDownload("archive contains no .app bundle")
        }

        let installed = Bundle.main.bundleURL
        let installedIdentity = signingIdentity(of: installed)
        let downloadedIdentity = signingIdentity(of: downloaded)
        guard !installedIdentity.isEmpty, installedIdentity == downloadedIdentity else {
            throw UpdateError.signatureMismatch(installed: installedIdentity,
                                                downloaded: downloadedIdentity)
        }

        let copy = "/usr/bin/ditto '\(downloaded.path)' '\(installed.path)'"
        if FileManager.default.isWritableFile(atPath: installed.path) {
            let r = try Shell.run("/usr/bin/ditto", [downloaded.path, installed.path])
            guard r.ok else { throw NixmcError.command(r.stderr) }
        } else {
            try AdminShell.run(copy)
        }
        try? FileManager.default.removeItem(at: staging)
        relaunch(installed)
    }

    /// First `Authority=` line from `codesign -dvvv` — the leaf signing
    /// certificate ("Developer ID Application: … (TEAMID)"). Comparing it
    /// between the installed and downloaded bundles is the authenticity gate.
    static func signingIdentity(of bundle: URL) -> String {
        guard let r = try? Shell.run("/usr/bin/codesign", ["-dvvv", bundle.path]) else { return "" }
        for line in r.stderr.split(whereSeparator: \.isNewline)
        where line.hasPrefix("Authority=") {
            return String(line.dropFirst("Authority=".count))
        }
        return ""
    }

    /// Reopen the (now replaced) bundle after this process exits.
    private static func relaunch(_ app: URL) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; /usr/bin/open '\(app.path)'"]
        try? p.run()
        DispatchQueue.main.async { NSApp.terminate(nil) }
    }

    private static func parseVersion(_ tag: String) -> [Int] {
        let core = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let numbers = core.split(separator: "-").first?.split(separator: ".")
            .compactMap { Int($0) } ?? []
        return numbers.count == 3 ? numbers : []
    }

    private static func isNewer(_ a: [Int], than b: [Int]) -> Bool {
        for (x, y) in zip(a, b) where x != y { return x > y }
        return a.count > b.count
    }
}
