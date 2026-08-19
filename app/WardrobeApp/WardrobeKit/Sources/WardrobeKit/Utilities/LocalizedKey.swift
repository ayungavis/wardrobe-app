import Foundation

enum LocalizedKey {
    static func resolve(_ key: String) -> String {
        String(localized: String.LocalizationValue(key), bundle: .module)
    }
}
