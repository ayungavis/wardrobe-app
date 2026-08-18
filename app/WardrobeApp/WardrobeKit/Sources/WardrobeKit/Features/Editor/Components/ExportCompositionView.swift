import CoreGraphics
import SwiftUI

/// Static composition rendered for export — uses the same label components
/// as the editor canvas, so output matches the preview.
struct ExportCompositionView: View {
    let image: CGImage
    let texts: [TextItem]
    let stickers: [StickerItem]
    let size: CGSize

    var body: some View {
        ZStack {
            // Aspect-fill, matching `CanvasPhotoLayer`.
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .clipped()

            ForEach(stickers) { item in
                StickerLabelView(emoji: item.emoji, fontSize: TextRendering.stickerFontSize(for: item, in: size))
                    .rotationEffect(.degrees(item.rotationDegrees))
                    .position(x: item.position.x * size.width, y: item.position.y * size.height)
            }

            ForEach(texts) { item in
                TextItemLabelView(item: TextContent(item), fontSize: TextRendering.fontSize(for: item, in: size))
                    .rotationEffect(.degrees(item.rotationDegrees))
                    .position(x: item.position.x * size.width, y: item.position.y * size.height)
            }
        }
        .frame(width: size.width, height: size.height)
    }
}
