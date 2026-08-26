import CoreGraphics
import SwiftUI

struct LayerContentView: View {
    let content: LayerContent
    let canvasSize: CGSize
    let image: (UUID) -> CGImage?

    var body: some View {
        switch content {
        case let .photo(content):
            PolaroidPhotoView(
                photo: image(content.photoID),
                width: canvasSize.width * PolaroidPhotoView.widthRatio
            )
        case let .text(text):
            TextItemLabelView(item: text, fontSize: TextRendering.baseFontSize(in: canvasSize))
        case let .sticker(sticker):
            StickerArtworkView(
                art: sticker.art,
                size: TextRendering.baseStickerFontSize(in: canvasSize),
                image: sticker.art.wardrobeItemID.flatMap(image)
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
