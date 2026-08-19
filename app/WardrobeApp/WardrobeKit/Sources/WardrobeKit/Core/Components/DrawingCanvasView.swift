import CoreGraphics
import SwiftUI

/// Renders a drawing's strokes. The editor canvas, the live session, and the
/// exporter all draw through here, so the file matches the screen.
///
/// `referenceWidth` is what keeps that true. A fitted layer is drawn into a box
/// smaller than the canvas, but a line's weight belongs to the canvas, not to
/// the box — deriving it from the box would make a trimmed drawing thinner than
/// the one you drew.
struct DrawingCanvasView: View {
    let content: DrawingContent
    let referenceWidth: CGFloat

    var body: some View {
        Canvas { context, size in
            for stroke in content.strokes {
                draw(stroke, in: &context, size: size)
            }
        }
        .accessibilityHidden(true)
    }

    private func draw(_ stroke: DrawingStroke, in context: inout GraphicsContext, size: CGSize) {
        let lineWidth = DrawingPath.lineWidth(for: stroke, referenceWidth: referenceWidth)
        let path = DrawingPath.path(for: stroke, in: size, dotWidth: lineWidth)

        // A single sample is already a filled dot; anything longer is a line.
        if stroke.points.count > 1 {
            context.stroke(
                path,
                with: .color(stroke.color.color),
                style: DrawingPath.strokeStyle(lineWidth: lineWidth)
            )
        } else {
            context.fill(path, with: .color(stroke.color.color))
        }
    }
}
