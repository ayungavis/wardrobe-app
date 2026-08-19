import CoreText
import Foundation
import os

public enum FontRegistration {
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
