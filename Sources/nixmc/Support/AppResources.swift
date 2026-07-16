import Foundation

/// Resources processed by SwiftPM for both an installed app and `swift run`.
///
/// Older SwiftPM-generated `Bundle.module` accessors look beside the `.app`
/// bundle, a location that cannot contain signed app resources. Resolve the
/// processed bundle ourselves from the app's Resources directory instead.
enum AppResources {
    private static let bundleName = "nixmc_nixmc.bundle"

    static let bundle: Bundle = {
        let candidates = [Bundle.main.resourceURL, Bundle.main.bundleURL]
            .compactMap { $0?.appendingPathComponent(bundleName) }

        for url in candidates {
            if let bundle = Bundle(url: url) {
                return bundle
            }
        }

        fatalError("could not load resource bundle: \(bundleName)")
    }()
}
