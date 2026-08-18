import CoreGraphics
import DesignSystem
import SwiftUI

/// A layer at 46 points, for the panel row.
///
/// Drawn per kind rather than by shrinking `LayerContentView`. Every size in
/// that view is a fraction of the canvas, so a true miniature would put text at
/// about four points and the polaroid at twenty-seven with its white border —
/// honest, and unreadable. What a row needs is recognisable, which is a
/// different job.
struct LayerThumbnailView: View {
    static let size: CGFloat = 46
    private static let cornerRadius: CGFloat = 11

    let content: LayerContent
    let photo: CGImage?

    var body: some View {
        artwork
            .frame(width: Self.size, height: Self.size)
            .clipShape(.rect(cornerRadius: Self.cornerRadius))
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var artwork: some View {
        switch content {
        case .photo:
            photoFill
        case let .text(text):
            textPreview(text)
        case let .sticker(sticker):
            StickerArtworkView(art: sticker.art, size: Self.size * 0.92)
        case let .drawing(drawing):
            DrawingCanvasView(content: drawing, referenceWidth: Self.size / drawing.widthScale)
                .background(AppColor.onMedia.opacity(0.08))
        }
    }

    /// The cropped capture itself, not the polaroid frame: at this size the
    /// border and lip would be most of the cell.
    @ViewBuilder
    private var photoFill: some View {
        if let photo {
            Image(decorative: photo, scale: 1)
                .resizable()
                .scaledToFill()
        } else {
            AppColor.onMedia.opacity(0.12)
        }
    }

    /// The layer's own colours on a specimen, the way a font menu shows one.
    private func textPreview(_ text: TextContent) -> some View {
        ZStack {
            textBackground(text)
            Text(verbatim: "Aa")
                .font(.system(size: 18, weight: .bold, design: text.fontStyle.design))
                .foregroundStyle(text.backgroundStyle == .solid ? text.textColor.contrastText : text.textColor.color)
        }
    }

    @ViewBuilder
    private func textBackground(_ text: TextContent) -> some View {
        switch text.backgroundStyle {
        case .none: AppColor.onMedia.opacity(0.10)
        case .solid: text.textColor.color
        case .translucent: AppColor.mediaBackground.opacity(0.52)
        }
    }
}

private extension DrawingContent {
    /// A fitted drawing is stored in a box smaller than the canvas, so the
    /// reference width it was drawn against is the box divided by that ratio —
    /// otherwise every trimmed drawing comes out thin.
    var widthScale: CGFloat {
        max(CGFloat(widthRatio), 0.001)
    }
}
