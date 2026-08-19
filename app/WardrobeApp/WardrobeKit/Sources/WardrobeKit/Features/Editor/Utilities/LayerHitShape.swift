import CoreGraphics
import SwiftUI

struct LayerHitShape: Shape {
    let content: LayerContent
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
