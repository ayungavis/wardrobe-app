import CoreGraphics
import Foundation
import SwiftUI

/// Which layer a touch landed on.
///
/// Asks `LayerHitShape` — the very shape `.contentShape` gives SwiftUI — so the
/// touch area is identical to the one taps already use, per-stroke logic for
/// drawings included.
enum CanvasHitTest {
    /// Topmost first, because that is what the user sees on top. A layer the
    /// caller may not act on still blocks the ones beneath it, the same way a
    /// locked layer swallows a touch today rather than passing it through.
    static func layerID(
        at point: CGPoint,
        in document: EditorDocument,
        canvasSize: CGSize,
        layerSizes: [UUID: CGSize]
    ) -> UUID? {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return nil }

        for layer in document.layers.reversed() {
            guard let size = layerSizes[layer.id], size.width > 0, size.height > 0,
                  let local = localPoint(point, layer: layer, size: size, canvasSize: canvasSize)
            else {
                continue
            }
            let shape = LayerHitShape(content: layer.content, referenceWidth: canvasSize.width)
            if shape.path(in: CGRect(origin: .zero, size: size)).contains(local) {
                return layer.id
            }
        }
        return nil
    }

    /// Undoes `canvasLayerTransform`, which applies scale, then rotation, then
    /// position — both effects anchored at the centre.
    private static func localPoint(
        _ point: CGPoint,
        layer: EditorLayer,
        size: CGSize,
        canvasSize: CGSize
    ) -> CGPoint? {
        let scale = layer.transform.scale
        guard scale > 0 else { return nil }

        let centre = CanvasGeometry.point(for: layer.transform.position, in: canvasSize)
        let dx = point.x - centre.x
        let dy = point.y - centre.y

        let radians = -layer.transform.rotationDegrees * .pi / 180
        let cosine = cos(radians)
        let sine = sin(radians)

        return CGPoint(
            x: size.width / 2 + (dx * cosine - dy * sine) / scale,
            y: size.height / 2 + (dx * sine + dy * cosine) / scale
        )
    }
}
