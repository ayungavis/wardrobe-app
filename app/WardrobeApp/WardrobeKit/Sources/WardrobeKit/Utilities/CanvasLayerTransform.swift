import CoreGraphics
import SwiftUI

extension View {
    /// Places a layer on the canvas.
    ///
    /// The **one** place a transform becomes modifiers. In the prototype the
    /// editor and the exporter each wrote out `scale → rotate → offset`
    /// themselves and agreed only because someone kept them agreeing; the
    /// moment they stopped, what you shared stopped matching what you saw. One
    /// call site each means they cannot disagree.
    func canvasLayerTransform(_ transform: ElementTransform, in canvasSize: CGSize) -> some View {
        scaleEffect(transform.scale)
            .rotationEffect(.degrees(transform.rotationDegrees))
            .position(CanvasGeometry.point(for: transform.position, in: canvasSize))
    }
}
