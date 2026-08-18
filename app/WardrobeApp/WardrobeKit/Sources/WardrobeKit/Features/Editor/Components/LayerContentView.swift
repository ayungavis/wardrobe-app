import CoreGraphics
import SwiftUI

/// Draws one layer's content at its **base** size.
///
/// Nothing here knows about scale, rotation, or position — the transform is
/// applied on top by `canvasLayerTransform`, the same way on the canvas and in
/// the export. Every size below is a fraction of the canvas, which is what lets
/// the exporter lay out at 1080×1920 and still get the picture on screen.
struct LayerContentView: View {
    let content: LayerContent
    let canvasSize: CGSize
    /// ponytail: one photo per document today. FR-093 (more than one) turns
    /// this into a lookup by `PhotoContent.photoID`.
    let photo: CGImage?

    var body: some View {
        switch content {
        case .photo:
            PolaroidPhotoView(photo: photo, width: canvasSize.width * PolaroidPhotoView.widthRatio)
        case let .text(text):
            TextItemLabelView(item: text, fontSize: TextRendering.baseFontSize(in: canvasSize))
        case let .sticker(sticker):
            StickerLabelView(
                emoji: sticker.emoji,
                fontSize: TextRendering.baseStickerFontSize(in: canvasSize)
            )
        case .drawing:
            // Drawings arrive with the drawing tool.
            EmptyView()
        }
    }
}
