import SwiftUI

// ponytail: system font until design picks a custom font; swap the base font
// here, register files in Resources/Fonts + UIAppFonts.

public enum AppFont {
    public static let largeTitle = Font.system(.largeTitle, design: .rounded).weight(.bold)
    public static let title = Font.system(.title2, design: .rounded).weight(.semibold)
    public static let body = Font.system(.body, design: .rounded)
    public static let caption = Font.system(.caption, design: .rounded)
    public static let customTitle = Font.custom("Allison-Regular", size: 128)
    public static let customSmallTitle = Font.custom("SeymourOne", size: 20)
    public static let roundedLargeTitle = Font.system(size: 36, weight: .bold, design: .rounded)
    public static let roundedTitle = Font.system(size: 24, weight: .bold, design: .rounded)
    public static let roundedTitle2 = Font.system(size: 20, weight: .bold, design: .rounded)
    public static let roundedCaption = Font.system(size: 12, weight: .bold, design: .rounded)

}
