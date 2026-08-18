import CoreGraphics
import Foundation

/// One discrete adjustment to a layer's transform (§19: move, resize, and
/// rotate in discrete steps, without a precision gesture).
///
/// Deliberately kept away from `CanvasSnapping`. FR-089's acceptance says
/// snapping "cannot prevent accessible discrete adjustments", and it would: the
/// 45°/4° rotation window swallows a 15° step taken near a multiple of 45, and
/// the tolerance around scale 2.0 pulls a 0.1 step straight back. A stepped
/// adjustment composes the transform itself and never asks the snapper.
enum LayerStep: Equatable {
    case left, right, up, down
    case bigger, smaller
    case rotateLeft, rotateRight
    case reset

    /// A step across, in unit space — roughly 20pt on an iPhone canvas, the
    /// prototype's nudge. Stored as a fraction so a panel row, which has no
    /// geometry of its own, never needs to know how big the canvas is.
    static let moveStep: CGFloat = 0.05
    static let scaleStep: CGFloat = 0.1
    static let rotationStep: Double = 15

    /// The canvas is always 9:16, so scaling the vertical step by the aspect
    /// ratio makes up and down cover the same visible distance as left and
    /// right.
    static var verticalMoveStep: CGFloat {
        moveStep * StoryCanvas.aspectRatio
    }

    static func apply(_ step: LayerStep, to transform: ElementTransform) -> ElementTransform {
        guard step != .reset else { return .identity }

        var stepped = transform
        switch step {
        case .left: stepped.position.x -= moveStep
        case .right: stepped.position.x += moveStep
        case .up: stepped.position.y -= verticalMoveStep
        case .down: stepped.position.y += verticalMoveStep
        case .bigger: stepped.scale += scaleStep
        case .smaller: stepped.scale -= scaleStep
        case .rotateLeft: stepped.rotationDegrees -= rotationStep
        case .rotateRight: stepped.rotationDegrees += rotationStep
        case .reset: break
        }
        stepped.position = onCanvas(stepped.position)
        return stepped.clamped()
    }

    /// Keeps a stepped layer on the canvas.
    ///
    /// `CanvasGeometry.constrainedPosition` is the real bound, but it needs the
    /// layer's rendered size in points and a panel row has no geometry. 0…1 is
    /// weaker and enough: a layer cannot be stepped out of reach, and the next
    /// gesture applies the real limit.
    static func onCanvas(_ position: CGPoint) -> CGPoint {
        CGPoint(x: min(max(position.x, 0), 1), y: min(max(position.y, 0), 1))
    }
}
