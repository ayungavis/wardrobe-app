import CoreGraphics
import Foundation

enum LayerStep: Equatable {
    case left, right, up, down
    case bigger, smaller
    case rotateLeft, rotateRight
    case reset

    static let moveStep: CGFloat = 0.05
    static let scaleStep: CGFloat = 0.1
    static let rotationStep: Double = 15

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

    static func onCanvas(_ position: CGPoint) -> CGPoint {
        CGPoint(x: min(max(position.x, 0), 1), y: min(max(position.y, 0), 1))
    }
}
