import CoreGraphics
import Foundation

/// The canvas's arithmetic, kept out of the views so it can be tested without
/// a finger.
///
/// Positions are unit space (0…1 across the canvas), matching `ElementTransform`
/// — sizes are points, because a layer's rendered box only exists in points.
/// Every function here converts between the two explicitly rather than letting
/// a point value leak into something that gets stored.
enum CanvasGeometry {
    /// How much of a layer must stay on the canvas after a drag. Below this a
    /// layer could be flung out of reach with no way to get it back.
    static let minimumVisibleLength: CGFloat = 44

    static func point(for position: CGPoint, in canvasSize: CGSize) -> CGPoint {
        CGPoint(x: position.x * canvasSize.width, y: position.y * canvasSize.height)
    }

    /// Converts a drag translation in points into a unit-space displacement.
    static func position(
        _ position: CGPoint,
        translatedBy translation: CGSize,
        in canvasSize: CGSize
    ) -> CGPoint {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return position }
        return CGPoint(
            x: position.x + translation.width / canvasSize.width,
            y: position.y + translation.height / canvasSize.height
        )
    }

    /// Pulls a layer back until `minimumVisibleLength` of it is on the canvas.
    ///
    /// Applied when the gesture ends, never during it — so a layer follows the
    /// finger honestly and then settles, which is what the prototype does and
    /// what stops the drag from feeling like it is fighting back.
    static func constrainedPosition(
        _ position: CGPoint,
        canvasSize: CGSize,
        layerSize: CGSize,
        scale: CGFloat,
        rotationDegrees: Double
    ) -> CGPoint {
        guard canvasSize.width > 0, canvasSize.height > 0,
              layerSize.width > 0, layerSize.height > 0
        else {
            return position
        }

        let halfExtents = rotatedHalfExtents(
            layerSize: layerSize, scale: scale, rotationDegrees: rotationDegrees
        )
        let visibleHalf = minimumVisibleLength / 2
        let horizontalLimit = max(canvasSize.width / 2 - min(halfExtents.width, visibleHalf), 0)
            / canvasSize.width
        let verticalLimit = max(canvasSize.height / 2 - min(halfExtents.height, visibleHalf), 0)
            / canvasSize.height

        return CGPoint(
            x: clamped(position.x, within: horizontalLimit),
            y: clamped(position.y, within: verticalLimit)
        )
    }

    /// The bottom-centre drop zone (FR-087). What is tested is the layer's own
    /// centre, not the finger: the layer visibly shrinks into the target, so
    /// the thing the user is aiming is the layer.
    static func isOverDeleteTarget(_ position: CGPoint) -> Bool {
        abs(position.x - 0.5) < 0.15 && position.y > 0.85
    }

    /// Half the axis-aligned box a rotated, scaled layer actually occupies.
    private static func rotatedHalfExtents(
        layerSize: CGSize,
        scale: CGFloat,
        rotationDegrees: Double
    ) -> CGSize {
        let safeScale = max(scale, ElementTransform.scaleRange.lowerBound)
        let halfWidth = layerSize.width * safeScale / 2
        let halfHeight = layerSize.height * safeScale / 2
        let radians = rotationDegrees * .pi / 180
        let cosine = abs(cos(radians))
        let sine = abs(sin(radians))

        return CGSize(
            width: halfWidth * cosine + halfHeight * sine,
            height: halfWidth * sine + halfHeight * cosine
        )
    }

    private static func clamped(_ value: CGFloat, within limit: CGFloat) -> CGFloat {
        min(max(value, 0.5 - limit), 0.5 + limit)
    }
}
