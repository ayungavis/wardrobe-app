import Foundation

/// Resolves localization keys that are assembled at runtime from a raw value.
enum LocalizedKey {
    /// The `String` parameter is load-bearing, and is the whole reason this
    /// function exists.
    ///
    /// Passing an *interpolated literal* to `String.LocalizationValue` does not
    /// build a key — `LocalizationValue` is `ExpressibleByStringInterpolation`,
    /// so it builds a **format** (`"editor.sticker.category.%@"`) plus an
    /// argument. The lookup then misses, and the fallback is that format with
    /// the argument substituted back in: the raw key, on screen, looking for
    /// all the world like a missing translation.
    ///
    /// Going through a variable calls `init(_ value: String)` instead, which
    /// makes the whole string the key. Every runtime-assembled key goes through
    /// here so there is one idiom rather than two that look alike.
    static func resolve(_ key: String) -> String {
        String(localized: String.LocalizationValue(key), bundle: .module)
    }
}
