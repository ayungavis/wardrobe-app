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
        let points = stroke.points.map { point in
            CGPoint(x: point.unitX * size.width, y: point.unitY * size.height)
        }
        guard let first = points.first else { return }

        let lineWidth = max(1, CGFloat(stroke.width.ratio) * referenceWidth)

        // A tap is a dot, not a line of zero length.
        guard points.count > 1 else {
            context.fill(
                Path(ellipseIn: CGRect(
                    x: first.x - lineWidth / 2, y: first.y - lineWidth / 2,
                    width: lineWidth, height: lineWidth
                )),
                with: .color(stroke.color.color)
            )
            return
        }

        // Midpoint quadratics: each sample becomes a control point and the curve
        // passes through the midpoints, which smooths finger jitter without
        // needing to know anything about the samples ahead.
        var path = Path()
        path.move(to: first)
        for index in 1 ..< points.count {
            let previous = points[index - 1]
            let current = points[index]
            let midpoint = CGPoint(x: (previous.x + current.x) / 2, y: (previous.y + current.y) / 2)
            path.addQuadCurve(to: midpoint, control: previous)
        }
        if let last = points.last {
            path.addLine(to: last)
        }

        context.stroke(
            path,
            with: .color(stroke.color.color),
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
        )
    }
}
