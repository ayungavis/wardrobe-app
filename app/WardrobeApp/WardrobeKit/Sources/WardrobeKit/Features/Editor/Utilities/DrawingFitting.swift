import CoreGraphics
import Foundation

/// Trims a finished drawing to its own content.
///
/// A drawing session paints across the whole canvas, but a layer the size of the
/// canvas is a bad layer: its hit region swallows every tap meant for what sits
/// beneath it, its selection outline is the whole picture, and "keep 44pt on
/// screen" means nothing. Fitting turns the session into an object the size of
/// the marks in it.
///
/// Pure arithmetic on purpose — this is the part that has to be right, and it
/// can be checked without a finger.
enum DrawingFitting {
    /// A drawing trimmed to its marks, and where to put it.
    struct Fitted: Equatable {
        var content: DrawingContent
        var transform: ElementTransform
    }

    /// Nil when there is nothing to fit — an empty session commits no layer.
    ///
    /// `canvasSize` decides how wide a stroke actually is, which is why the box
    /// has to grow by each stroke's own radius: a fat line drawn along the edge
    /// of its own bounding box would otherwise be sliced in half.
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

    /// The union of every point, each grown by half the weight of the line it
    /// belongs to plus a hair of breathing room.
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
