import Foundation

/// Localized string honoring the in-app Language setting ("en" / "id"), not just the system language.
func L(_ key: String) -> String {
    let lang = UserDefaults.standard.string(forKey: "language") ?? "en"
    let bundle = Bundle.module.path(forResource: lang, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .module
    return bundle.localizedString(forKey: key, value: key, table: nil)
}
