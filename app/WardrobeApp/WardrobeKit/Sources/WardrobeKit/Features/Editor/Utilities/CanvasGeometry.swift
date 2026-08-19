import CoreGraphics
import Foundation

enum CanvasGeometry {
    static let minimumVisibleLength: CGFloat = 44

    static func point(for position: CGPoint, in canvasSize: CGSize) -> CGPoint {
        CGPoint(x: position.x * canvasSize.width, y: position.y * canvasSize.height)
    }

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

    static func isOverDeleteTarget(_ position: CGPoint) -> Bool {
        abs(position.x - 0.5) < 0.15 && position.y > 0.85
    }

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
