import SwiftUI

/// A committed sticker on the canvas — drag, pinch and rotate handled by
/// `ManipulatableOverlayView`.
struct CommittedStickerView: View {
    let item: StickerItem
    let canvasSize: CGSize
    let onMove: (CGPoint) -> Void
    let onScale: (CGFloat) -> Void
    let onRotate: (Double) -> Void
    let onDragActive: (Bool) -> Void
    let onManipulationEnd: () -> Void

    var body: some View {
        ManipulatableOverlayView(
            position: item.position,
            scale: item.scale,
            rotationDegrees: item.rotationDegrees,
            canvasSize: canvasSize,
            onMove: onMove,
            onScale: onScale,
            onRotate: onRotate,
            onDragActive: onDragActive,
            onManipulationEnd: onManipulationEnd
        ) {
            StickerLabelView(item: item, fontSize: TextRendering.stickerFontSize(for: item, in: canvasSize))
        }
    }
}
