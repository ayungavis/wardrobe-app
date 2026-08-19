import SwiftUI

public enum AppColor {
    public static let background = Color("background", bundle: .module)
    public static let surface = Color("surface", bundle: .module)
    // ponytail: the asset-catalogue token was swapped for the semantic colour
    // during the paper-texture redesign; four screens now force black on that
    // texture, so dark mode is black-on-dark there. Restore the token or commit
    // to a light-only look — a design call, not a mechanical one.
    public static let textPrimary = Color.primary
    public static let textSecondary = Color("textSecondary", bundle: .module)
    public static let accent = Color("accent", bundle: .module)
    public static let destructive = Color("destructive", bundle: .module)
    public static let warning = Color("warning", bundle: .module)

    public static let mediaBackground = Color("mediaBackground", bundle: .module)
    public static let mediaSurface = Color("mediaSurface", bundle: .module)
    public static let onMedia = Color("onMedia", bundle: .module)
    public static let pink = Color("appPink", bundle: .module)
}
