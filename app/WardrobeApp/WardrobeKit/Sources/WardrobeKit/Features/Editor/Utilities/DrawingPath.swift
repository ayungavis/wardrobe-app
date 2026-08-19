import CoreGraphics
import SwiftUI

enum DrawingPath {
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

    static func lineWidth(for stroke: DrawingStroke, referenceWidth: CGFloat) -> CGFloat {
        max(1, CGFloat(stroke.width.ratio) * referenceWidth)
    }

    static func strokeStyle(lineWidth: CGFloat) -> StrokeStyle {
        StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
    }
}
