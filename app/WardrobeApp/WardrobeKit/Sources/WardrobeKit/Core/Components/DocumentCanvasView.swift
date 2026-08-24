import CoreGraphics
import SwiftUI

struct DocumentCanvasView: View {
    let document: EditorDocument
    let photo: (UUID) -> CGImage?
    let size: CGSize

    var body: some View {
        ZStack {
            CanvasBackgroundView(background: document.background, photo: photo)

            ForEach(Array(document.layers.enumerated()), id: \.element.id) { index, layer in
                LayerContentView(content: layer.content, canvasSize: size, photo: photo)
                    .canvasLayerTransform(layer.transform, in: size)
                    .zIndex(Double(index))
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }
}
