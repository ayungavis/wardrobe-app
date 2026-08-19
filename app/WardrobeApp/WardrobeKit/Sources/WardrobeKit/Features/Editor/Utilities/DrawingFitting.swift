import CoreGraphics
import Foundation

enum DrawingFitting {
    struct Fitted: Equatable {
        var content: DrawingContent
        var transform: ElementTransform
    }

    static func fit(_ content: DrawingContent, canvasSize: CGSize) -> Fitted? {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return nil }

        let strokes = content.strokes.compactMap { $0.sanitized() }
        guard !strokes.isEmpty else { return nil }

        guard var box = boundingBox(of: strokes, canvasSize: canvasSize) else { return nil }
        box = box.intersection(CGRect(origin: .zero, size: canvasSize))
        guard box.width > 0, box.height > 0 else { return nil }

        let fitted = DrawingContent(
            strokes: strokes.map { renormalise($0, into: box, canvasSize: canvasSize) },
            widthRatio: box.width / canvasSize.width,
            heightRatio: box.height / canvasSize.height
        )

        return Fitted(
            content: fitted,
            transform: ElementTransform(
                position: CGPoint(x: box.midX / canvasSize.width, y: box.midY / canvasSize.height)
            )
        )
    }

    private static func boundingBox(of strokes: [DrawingStroke], canvasSize: CGSize) -> CGRect? {
        var box: CGRect?

        for stroke in strokes {
            let padding = strokeRadius(stroke, canvasWidth: canvasSize.width) + 2
            for point in stroke.points {
                let rect = CGRect(
                    x: point.unitX * canvasSize.width - padding,
                    y: point.unitY * canvasSize.height - padding,
                    width: padding * 2,
                    height: padding * 2
                )
                box = box.map { $0.union(rect) } ?? rect
            }
        }

        return box
    }

    private static func renormalise(
        _ stroke: DrawingStroke,
        into box: CGRect,
        canvasSize: CGSize
    ) -> DrawingStroke {
        var moved = stroke
        moved.points = stroke.points.map { point in
            DrawingPoint(
                unitX: (point.unitX * canvasSize.width - box.minX) / box.width,
                unitY: (point.unitY * canvasSize.height - box.minY) / box.height
            )
        }
        return moved
    }

    static func strokeRadius(_ stroke: DrawingStroke, canvasWidth: CGFloat) -> CGFloat {
        max(1, CGFloat(stroke.width.ratio) * canvasWidth) / 2
    }
}
