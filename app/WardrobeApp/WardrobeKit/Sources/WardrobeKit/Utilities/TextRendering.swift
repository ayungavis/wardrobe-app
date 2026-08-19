import CoreGraphics

enum TextRendering {
    static func baseFontSize(in size: CGSize) -> CGFloat {
        0.08 * min(size.width, size.height)
    }

    static func baseStickerFontSize(in size: CGSize) -> CGFloat {
        0.15 * min(size.width, size.height)
    }
}
