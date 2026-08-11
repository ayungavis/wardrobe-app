import SwiftUI

/// Semantic colors backed by the asset catalog (light/dark variants live there).
/// Views must use these instead of `Color` literals.
public enum AppColor {
    public static let background = Color("background", bundle: .module)
    public static let surface = Color("surface", bundle: .module)
    public static let textPrimary = Color("textPrimary", bundle: .module)
    public static let textSecondary = Color("textSecondary", bundle: .module)
    public static let accent = Color("accent", bundle: .module)

    // Media surfaces (camera/editor) commit to a dark look regardless of the
    // system appearance — like every story-style editor.
    public static let mediaBackground = Color("mediaBackground", bundle: .module)
    public static let onMedia = Color("onMedia", bundle: .module)
}
