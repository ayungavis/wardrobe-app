import CoreGraphics
import SwiftUI

/// Draws one layer's content at its **base** size.
///
/// Nothing here knows about scale, rotation, or position — `EditorLayerView`
/// owns the transform. That split is what lets the canvas apply a
/// `scaleEffect` while the exporter bakes the same scale into a font size and
/// still land on identical pixels.
struct LayerContentView: View {
    let content: LayerContent
    let canvasSize: CGSize

    var body: some View {
        switch content {
        case let .text(text):
            TextItemLabelView(item: text, fontSize: TextRendering.baseFontSize(in: canvasSize))
        case let .sticker(sticker):
            StickerLabelView(
                emoji: sticker.emoji,
                fontSize: TextRendering.baseStickerFontSize(in: canvasSize)
            )
        case .photo, .drawing:
            // The photo fills the canvas as its background until it gets a
            // polaroid frame to sit in; drawings arrive with the drawing tool.
            EmptyView()
        }
    }
}
