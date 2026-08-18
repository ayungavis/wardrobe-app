import CoreGraphics
import Testing
@testable import WardrobeKit

/// §19's discrete adjustments. They are the path for anyone who cannot pinch or
/// rotate, so the arithmetic is pinned rather than eyeballed.
struct LayerStepTests {
    @Test func oppositeStepsCancelOut() {
        let stepped = LayerStep.apply(.left, to: LayerStep.apply(.right, to: .identity))

        #expect(abs(stepped.position.x - 0.5) < 0.0001)
    }

    /// A step up must cover the same visible distance as a step right, which on
    /// a 9:16 canvas means a smaller number in unit space.
    @Test func aVerticalStepCoversTheSameDistanceAsAHorizontalOne() {
        let across = LayerStep.apply(.right, to: .identity).position.x - 0.5
        let down = LayerStep.apply(.down, to: .identity).position.y - 0.5

        let vertical = down * StoryCanvas.exportSize.height
        let horizontal = across * StoryCanvas.exportSize.width
        #expect(abs(vertical - horizontal) < 0.0001)
    }

    /// Stepping repeatedly at the edge stops rather than walking the layer off
    /// the canvas, where nothing could reach it again.
    @Test func stepsCannotWalkALayerOffTheCanvas() {
        var transform = ElementTransform.identity
        for _ in 0 ..< 40 {
            transform = LayerStep.apply(.right, to: transform)
        }

        #expect(transform.position.x == 1)
    }

    @Test func theScaleStepStopsAtTheDocumentBound() {
        var transform = ElementTransform.identity
        for _ in 0 ..< 100 {
            transform = LayerStep.apply(.bigger, to: transform)
        }

        #expect(transform.scale == ElementTransform.scaleRange.upperBound)
    }

    @Test func smallerStepsBackDown() {
        let transform = LayerStep.apply(.smaller, to: ElementTransform(scale: 2))

        #expect(transform.scale == 2 - LayerStep.scaleStep)
    }

    /// FR-089's acceptance, literally: "snapping cannot prevent accessible
    /// discrete adjustments". 44° is inside the snapper's 4° window around 45,
    /// so a stepped rotation that consulted it would never leave 45.
    @Test func aSteppedRotationIgnoresTheSnapper() {
        let transform = LayerStep.apply(.rotateRight, to: ElementTransform(rotationDegrees: 44))

        #expect(transform.rotationDegrees == 59)
        #expect(CanvasSnapping.rotationSnap(for: 44) == 45)
    }

    @Test func rotatingLeftAndRightCancelOut() {
        let start = ElementTransform(rotationDegrees: 30)

        let stepped = LayerStep.apply(.rotateLeft, to: LayerStep.apply(.rotateRight, to: start))

        #expect(stepped.rotationDegrees == 30)
    }

    @Test func resetReturnsEverythingAtOnce() {
        let moved = ElementTransform(
            position: CGPoint(x: 0.2, y: 0.9), scale: 3, rotationDegrees: 42
        )

        #expect(LayerStep.apply(.reset, to: moved) == .identity)
    }
}
