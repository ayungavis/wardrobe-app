import CoreText
import Foundation
import os

/// Registers the bundled fonts with Core Text.
///
/// A Swift package cannot use `UIAppFonts`: that key is read from the app's own
/// `Info.plist`, and these files live in the package bundle. So they are
/// registered at launch instead, before any `Font.custom` lookup runs.
public enum FontRegistration {
    /// DesignSystem must not depend on WardrobeKit, so this cannot use `Log` —
    /// it keeps its own logger rather than inverting that dependency.
    private static let log = Logger(subsystem: "com.wardrobeapp.designsystem", category: "fonts")

    public static func registerCustomFonts() {
        for name in ["Allison-Regular", "SeymourOne-Regular"] {
            guard let url = Bundle.module.url(forResource: name, withExtension: "ttf") else {
                log.error("Font file missing from bundle: \(name, privacy: .public)")
                continue
            }
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) {
                log.error("Font failed to register: \(name, privacy: .public)")
            }
        }
    }
}
