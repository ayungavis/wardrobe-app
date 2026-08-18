import CoreGraphics
import SwiftUI

/// How a stroke becomes a shape.
///
/// One place, because two things need the same answer: the canvas draws it, and
/// hit-testing decides whether a finger landed on it. Built twice they would
/// drift exactly where it matters most — the midpoint curve below means a
/// straight-polyline rebuild misses hardest on the curviest strokes, which is
/// where a user is most sure they touched the line.
enum DrawingPath {
    /// Midpoint quadratics: each sample becomes a control point and the curve
    /// passes through the midpoints, which smooths finger jitter without
    /// needing to know anything about the samples ahead.
    ///
    /// A single sample is a dot, not a line of zero length.
    static func path(for stroke: DrawingStroke, in size: CGSize, dotWidth: CGFloat) -> Path {
        let points = stroke.points.map { point in
            CGPoint(x: point.unitX * size.width, y: point.unitY * size.height)
        }
        guard let first = points.first else { return Path() }

        guard points.count > 1 else {
            return Path(ellipseIn: CGRect(
                x: first.x - dotWidth / 2, y: first.y - dotWidth / 2,
                width: dotWidth, height: dotWidth
            ))
        }

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
        return path
    }

    /// A stroke's weight belongs to the canvas it was drawn on, not to the box
    /// it ends up in, so it is measured against `referenceWidth`.
    static func lineWidth(for stroke: DrawingStroke, referenceWidth: CGFloat) -> CGFloat {
        max(1, CGFloat(stroke.width.ratio) * referenceWidth)
    }

    static func strokeStyle(lineWidth: CGFloat) -> StrokeStyle {
        StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
    }
}
