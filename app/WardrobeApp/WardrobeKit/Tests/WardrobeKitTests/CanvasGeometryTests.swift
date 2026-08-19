import CoreGraphics
import Testing
@testable import WardrobeKit

/// The canvas arithmetic, tested without a finger. Everything here decides
/// where a layer ends up after a gesture, so a wrong number is a layer someone
/// cannot reach.
struct CanvasGeometryTests {
    private let canvas = CGSize(width: 300, height: 540)

    // MARK: Unit ↔ points

    @Test func aTranslationInPointsBecomesAFractionOfTheCanvas() {
        let moved = CanvasGeometry.position(
            CGPoint(x: 0.5, y: 0.5), translatedBy: CGSize(width: 30, height: -54), in: canvas
        )

        #expect(abs(moved.x - 0.6) < 0.0001)
        #expect(abs(moved.y - 0.4) < 0.0001)
    }

    /// The canvas has no size before its first layout pass; dividing by it then
    /// would send every layer to infinity.
    @Test func aCanvasWithNoSizeYetMovesNothing() {
        let position = CGPoint(x: 0.25, y: 0.75)

        #expect(CanvasGeometry.position(
            position, translatedBy: CGSize(width: 100, height: 100), in: .zero
        ) == position)
    }

    @Test func unitPositionsConvertToCanvasPoints() {
        #expect(CanvasGeometry.point(for: CGPoint(x: 0.5, y: 0.25), in: canvas)
            == CGPoint(x: 150, y: 135))
    }

    // MARK: Staying reachable

    @Test func aLayerInsideTheCanvasIsLeftExactlyWhereItIs() {
        let position = CGPoint(x: 0.4, y: 0.6)

        let settled = CanvasGeometry.constrainedPosition(
            position, canvasSize: canvas, layerSize: CGSize(width: 100, height: 40),
            scale: 1, rotationDegrees: 0
        )

        #expect(settled == position)
    }

    /// Dragged far off the right edge, it settles back to the point where
    /// `minimumVisibleLength / 2` of it is still on the canvas.
    @Test func aLayerDraggedOffTheCanvasSettlesBackWithinReach() {
        let settled = CanvasGeometry.constrainedPosition(
            CGPoint(x: 3, y: 0.5), canvasSize: canvas, layerSize: CGSize(width: 100, height: 40),
            scale: 1, rotationDegrees: 0
        )

        // Half the layer is 50pt, wider than the 22pt that must stay visible,
        // so the centre stops 22pt short of the right edge.
        #expect(abs(settled.x * canvas.width - (canvas.width - 22)) < 0.001)
    }

    /// A layer smaller than the minimum cannot leave a 44pt trace, so the rule
    /// degrades to "all of it stays on" rather than pushing it off.
    @Test func aLayerSmallerThanTheMinimumStaysFullyOnTheCanvas() {
        let settled = CanvasGeometry.constrainedPosition(
            CGPoint(x: 3, y: 0.5), canvasSize: canvas, layerSize: CGSize(width: 20, height: 20),
            scale: 1, rotationDegrees: 0
        )

        #expect(abs(settled.x * canvas.width - (canvas.width - 10)) < 0.001)
    }

    /// Rotation changes the box a layer occupies, so it has to change the limit
    /// too — a rotated label reaches further sideways than an upright one.
    @Test func rotationChangesHowFarALayerMayGo() {
        let layer = CGSize(width: 100, height: 40)

        let upright = CanvasGeometry.constrainedPosition(
            CGPoint(x: 3, y: 0.5), canvasSize: canvas, layerSize: layer, scale: 1, rotationDegrees: 0
        )
        let turned = CanvasGeometry.constrainedPosition(
            CGPoint(x: 3, y: 0.5), canvasSize: canvas, layerSize: layer, scale: 1, rotationDegrees: 90
        )

        // Turned on its side the half-width is 20pt — under the 22pt minimum —
        // so it may travel further before the rule bites.
        #expect(turned.x > upright.x)
        #expect(abs(turned.x * canvas.width - (canvas.width - 20)) < 0.001)
    }

    @Test func scalingUpPullsALayerBackSooner() {
        let layer = CGSize(width: 20, height: 20)

        let small = CanvasGeometry.constrainedPosition(
            CGPoint(x: 3, y: 0.5), canvasSize: canvas, layerSize: layer, scale: 1, rotationDegrees: 0
        )
        let large = CanvasGeometry.constrainedPosition(
            CGPoint(x: 3, y: 0.5), canvasSize: canvas, layerSize: layer, scale: 4, rotationDegrees: 0
        )

        #expect(large.x < small.x)
    }

    @Test func aLayerWithNoMeasuredSizeIsLeftAlone() {
        let position = CGPoint(x: 5, y: 5)

        #expect(CanvasGeometry.constrainedPosition(
            position, canvasSize: canvas, layerSize: .zero, scale: 1, rotationDegrees: 0
        ) == position)
    }

    // MARK: The delete zone (FR-087)

    @Test func theDeleteZoneIsTheBottomCentre() {
        #expect(CanvasGeometry.isOverDeleteTarget(CGPoint(x: 0.5, y: 0.9)))
        #expect(CanvasGeometry.isOverDeleteTarget(CGPoint(x: 0.36, y: 0.95)))
    }

    @Test func theRestOfTheCanvasIsNotTheDeleteZone() {
        #expect(!CanvasGeometry.isOverDeleteTarget(CGPoint(x: 0.5, y: 0.5)))
        // Just above the zone, and just outside it sideways.
        #expect(!CanvasGeometry.isOverDeleteTarget(CGPoint(x: 0.5, y: 0.85)))
        #expect(!CanvasGeometry.isOverDeleteTarget(CGPoint(x: 0.7, y: 0.95)))
        #expect(!CanvasGeometry.isOverDeleteTarget(CGPoint(x: 0.5, y: 0.1)))
    }

    // MARK: Scale bounds

    @Test func scaleIsHeldInsideTheDocumentsRange() {
        #expect(ElementTransform.clampedScale(9) == ElementTransform.scaleRange.upperBound)
        #expect(ElementTransform.clampedScale(0.01) == ElementTransform.scaleRange.lowerBound)
        #expect(ElementTransform.clampedScale(2) == 2)
    }

    /// A pinch that divides by zero produces NaN; storing it would make the
    /// layer vanish with no way to bring it back.
    @Test func aScaleThatIsNotANumberFallsBackToLifeSize() {
        #expect(ElementTransform.clampedScale(.nan) == 1)
        #expect(ElementTransform.clampedScale(.infinity) == 1)
    }
}
