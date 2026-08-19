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
    /// A lookup rather than one image: a document can hold more than one photo
    /// layer (FR-093), and handing the same pixels to every layer drew the same
    /// picture twice.
    let photo: (String) -> CGImage?

    var body: some View {
        switch content {
        case let .photo(content):
            PolaroidPhotoView(
                photo: photo(content.photoID),
                width: canvasSize.width * PolaroidPhotoView.widthRatio
            )
        case let .text(text):
            TextItemLabelView(item: text, fontSize: TextRendering.baseFontSize(in: canvasSize))
        case let .sticker(sticker):
            StickerArtworkView(
                art: sticker.art,
                size: TextRendering.baseStickerFontSize(in: canvasSize)
            )
        case let .drawing(drawing):
            DrawingCanvasView(content: drawing, referenceWidth: canvasSize.width)
                .frame(
                    width: canvasSize.width * drawing.widthRatio,
                    height: canvasSize.height * drawing.heightRatio
                )
        }
    }
}
