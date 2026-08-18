import CoreGraphics
import SwiftUI

/// The document drawn flat, with no interaction — what the exporter rasterises
/// at 1080×1920 (FR-032).
///
/// It shares `LayerContentView` and `canvasLayerTransform` with the editor's
/// interactive canvas, which is what makes the file match the screen. What it
/// deliberately does not share is chrome: selection outlines, the delete
/// target, and the canvas's rounded corners belong to editing, not to the
/// picture.
struct DocumentCanvasView: View {
    let document: EditorDocument
    let photo: CGImage?
    let size: CGSize

    var body: some View {
        ZStack {
            CanvasBackgroundView(background: document.background)

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
