import CoreGraphics
import SwiftUI

extension View {
    func canvasLayerTransform(_ transform: ElementTransform, in canvasSize: CGSize) -> some View {
        scaleEffect(transform.scale)
            .rotationEffect(.degrees(transform.rotationDegrees))
            .position(CanvasGeometry.point(for: transform.position, in: canvasSize))
    }
}
