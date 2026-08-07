import SwiftUI

// ponytail: system font until design picks a custom font; swap the base font
// here, register files in Resources/Fonts + UIAppFonts.

/// Text styles built on system text styles so Dynamic Type works for free.
public enum AppFont {
    public static let largeTitle = Font.largeTitle.weight(.bold)
    public static let title = Font.title2.weight(.semibold)
    public static let body = Font.body
    public static let caption = Font.caption
}
