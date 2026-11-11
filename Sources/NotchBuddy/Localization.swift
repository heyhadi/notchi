import Foundation

/// Safe lookup for the resource bundle that checks Bundle.main.resourceURL first,
/// avoiding fatal errors when running from a packaged .app bundle.
private let resourceBundle: Bundle = {
    let bundleName = "NotchBuddy_NotchBuddy.bundle"

    if let resourceURL = Bundle.main.resourceURL {
        let bundleURL = resourceURL.appendingPathComponent(bundleName)
        if let bundle = Bundle(url: bundleURL) {
            return bundle
        }
    }

    if let execURL = Bundle.main.executableURL {
        let bundleURL = execURL.deletingLastPathComponent().appendingPathComponent(bundleName)
        if let bundle = Bundle(url: bundleURL) {
            return bundle
        }
    }

    #if SWIFT_PACKAGE
    return Bundle.module
    #else
    return Bundle.main
    #endif
}()

/// Localized string honoring the in-app Language setting ("en" / "id"), not just the system language.
func L(_ key: String) -> String {
    let lang = UserDefaults.standard.string(forKey: "language") ?? "en"
    let baseBundle = resourceBundle
    let langBundle = baseBundle.path(forResource: lang, ofType: "lproj").flatMap(Bundle.init(path:)) ?? baseBundle
    return langBundle.localizedString(forKey: key, value: key, table: nil)
}
