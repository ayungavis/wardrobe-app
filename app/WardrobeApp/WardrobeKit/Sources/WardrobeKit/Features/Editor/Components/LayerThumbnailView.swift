import CoreGraphics
import DesignSystem
import SwiftUI

struct LayerThumbnailView: View {
    static let size: CGFloat = 46
    private static let cornerRadius: CGFloat = 11

    let content: LayerContent
    let photo: (UUID) -> CGImage?

    var body: some View {
        artwork
            .frame(width: Self.size, height: Self.size)
            .clipShape(.rect(cornerRadius: Self.cornerRadius))
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var artwork: some View {
        switch content {
        case let .photo(content):
            photoFill(content.photoID)
        case let .text(text):
            textPreview(text)
        case let .sticker(sticker):
            StickerArtworkView(art: sticker.art, size: Self.size * 0.92)
        case let .drawing(drawing):
            DrawingCanvasView(content: drawing, referenceWidth: Self.size / drawing.widthScale)
                .background(AppColor.onMedia.opacity(0.08))
        }
    }

    @ViewBuilder
    private func photoFill(_ photoID: UUID) -> some View {
        if let photo = photo(photoID) {
            Image(decorative: photo, scale: 1)
                .resizable()
                .scaledToFill()
        } else {
            AppColor.onMedia.opacity(0.12)
        }
    }

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
    var widthScale: CGFloat {
        max(CGFloat(widthRatio), 0.001)
    }
}
