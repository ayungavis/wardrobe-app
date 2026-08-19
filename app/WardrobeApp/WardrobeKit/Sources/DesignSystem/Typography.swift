import SwiftUI

// ponytail: system font until design picks a custom font; swap the base font
// here, register files in Resources/Fonts + UIAppFonts.

public enum AppFont {
    public static let largeTitle = Font.largeTitle.weight(.bold)
    public static let title = Font.title2.weight(.semibold)
    public static let body = Font.body
    public static let caption = Font.caption
    public static let customTitle = Font.custom("Allison-Regular", size: 128)
    public static let customSmallTitle = Font.custom("SeymourOne", size: 20)
}
