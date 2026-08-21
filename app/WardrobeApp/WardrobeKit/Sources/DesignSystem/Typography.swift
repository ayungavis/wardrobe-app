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
    public static let roundedLargeTitle = Font.system(size: 36, weight: .bold, design: .rounded)
    public static let roundedTitle = Font.system(size: 24, weight: .bold, design: .rounded)
    public static let roundedCaption = Font.system(size: 12, weight: .bold, design: .rounded)

}
