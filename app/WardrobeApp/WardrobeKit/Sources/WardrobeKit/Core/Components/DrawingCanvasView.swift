import CoreGraphics
import SwiftUI

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
