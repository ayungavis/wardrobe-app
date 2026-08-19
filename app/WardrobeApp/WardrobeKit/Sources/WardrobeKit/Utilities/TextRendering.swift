import CoreGraphics

/// Shared layer sizing. A layer draws at its base size and its transform is
/// applied on top — on the canvas and in the export alike, through the same
/// modifier, so there is nothing left for the two to disagree about.
enum TextRendering {
    static func baseFontSize(in size: CGSize) -> CGFloat {
        0.08 * min(size.width, size.height)
    }

    static func baseStickerFontSize(in size: CGSize) -> CGFloat {
        0.15 * min(size.width, size.height)
    }
}
