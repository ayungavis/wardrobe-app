import DesignSystem
import SwiftUI

/// A committed text item on the canvas — tap to edit content; drag, pinch and
/// rotate handled by `ManipulatableOverlay`.
struct CommittedTextView: View {
    let item: TextItem
    let canvasSize: CGSize
    let onTap: () -> Void
    let onMove: (CGPoint) -> Void
    let onScale: (CGFloat) -> Void
    let onRotate: (Double) -> Void
    let onDragActive: (Bool) -> Void
    let onManipulationEnd: () -> Void

    var body: some View {
        ManipulatableOverlay(
            position: item.position,
            scale: item.scale,
            rotationDegrees: item.rotationDegrees,
            canvasSize: canvasSize,
            onTap: onTap,
            onMove: onMove,
            onScale: onScale,
            onRotate: onRotate,
            onDragActive: onDragActive,
            onManipulationEnd: onManipulationEnd
        ) {
            TextItemLabel(item: item, fontSize: TextRendering.fontSize(for: item, in: canvasSize))
        }
    }
}
