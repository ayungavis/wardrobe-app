import SwiftUI

/// Semantic colors backed by the asset catalog (light/dark variants live there).
/// Views must use these instead of `Color` literals.
public enum AppColor {
    public static let background = Color("background", bundle: .module)
    public static let surface = Color("surface", bundle: .module)
    public static let textPrimary = Color("textPrimary", bundle: .module)
    public static let textSecondary = Color("textSecondary", bundle: .module)
    public static let accent = Color("accent", bundle: .module)
}
