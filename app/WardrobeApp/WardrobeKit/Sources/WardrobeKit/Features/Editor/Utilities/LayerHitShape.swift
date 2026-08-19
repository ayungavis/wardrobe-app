import CoreGraphics
import SwiftUI

/// Where a finger has to land to hit a layer.
///
/// For a photo, a text pill, and a sticker that is the whole box — they fill it.
/// A drawing does not: one thin diagonal has a bounding box that is almost
/// entirely empty, and a rectangle there swallows every tap inside it, leaving
/// the layers underneath unreachable with nothing on screen explaining why.
///
/// One type that branches inside rather than two shapes at the call site, so no
/// `AnyShape` is needed — CLAUDE.md treats that as the same family as `AnyView`.
struct LayerHitShape: Shape {
    let content: LayerContent
    /// The canvas width the strokes were drawn against, which is what their
    /// weight is measured in.
    let referenceWidth: CGFloat

    /// ponytail: a stroke thickened to exactly its drawn width is nearly
    /// impossible to hit with a finger, so this is the floor. 32 rather than
    /// §19's 44 because that number is about *controls*, and selecting a layer
    /// already has a non-gesture path of its own through the layer panel. Tune
    /// it here if it feels mean or greedy.
    static let minimumTouchWidth: CGFloat = 32

    func path(in rect: CGRect) -> Path {
        guard case let .drawing(drawing) = content else { return Path(rect) }

        var path = Path()
        for stroke in drawing.strokes {
            let width = max(
                DrawingPath.lineWidth(for: stroke, referenceWidth: referenceWidth),
                Self.minimumTouchWidth
            )
            let line = DrawingPath.path(for: stroke, in: rect.size, dotWidth: width)
            path.addPath(line.strokedPath(DrawingPath.strokeStyle(lineWidth: width)))
        }
        return path
    }
}
