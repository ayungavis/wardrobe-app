import CoreGraphics
import Foundation
import Testing
@testable import WardrobeKit

/// FR-089. Snapping is advisory: it may help, it may never trap.
struct CanvasSnappingTests {
    private let canvas = CGSize(width: 400, height: 800)

    private func snap(
        from position: CGPoint = CGPoint(x: 0.5, y: 0.5),
        scale: CGFloat = 1,
        rotationDegrees: Double = 0,
        translation: CGSize = .zero,
        magnification: CGFloat = 1,
        rotationDelta: Double = 0
    ) -> CanvasSnap {
        CanvasSnapping.snap(
            committed: ElementTransform(
                position: position, scale: scale, rotationDegrees: rotationDegrees
            ),
            translation: translation,
            magnification: magnification,
            rotationDelta: rotationDelta,
            canvasSize: canvas
        )
    }

    // MARK: Position

    /// 8pt of a 400pt-wide canvas is 0.02 in unit space.
    @Test func aLayerNearTheCentreLineIsPulledOntoIt() {
        let result = snap(from: CGPoint(x: 0.4, y: 0.5), translation: CGSize(width: 39, height: 0))

        // 0.4 + 39/400 = 0.4975, within the window.
        #expect(result.transform.position.x == 0.5)
        #expect(result.alignment == .centred)
    }

    /// The first acceptance clause: outside the window nothing is captured, so
    /// a transform can always be continued.
    @Test func aLayerPastTheWindowIsLeftWhereTheFingerPutIt() {
        let result = snap(from: CGPoint(x: 0.5, y: 0.5), translation: CGSize(width: 40, height: 0))

        #expect(abs(result.transform.position.x - 0.6) < 0.0001)
        #expect(!result.alignment.showsVerticalLine)
    }

    @Test func eachAxisSnapsOnItsOwn() {
        let result = snap(from: CGPoint(x: 0.5, y: 0.2), translation: CGSize(width: 1, height: 1))

        #expect(result.transform.position.x == 0.5)
        #expect(abs(result.transform.position.y - 0.20125) < 0.0001)
        #expect(result.alignment == .centredHorizontally)
    }

    /// The prototype snapped position on any interaction, so a layer parked a
    /// few points off centre jumped there the moment it was pinched.
    @Test func aPinchWithNoDragNeverMovesTheLayer() {
        let parked = CGPoint(x: 0.505, y: 0.503)

        let result = snap(from: parked, magnification: 1.4)

        #expect(result.transform.position == parked)
        #expect(result.alignment == .none)
    }

    @Test func aCanvasWithNoSizeYetAlignsNothing() {
        #expect(CanvasSnapping.alignment(of: CGPoint(x: 0.5, y: 0.5), in: .zero) == .none)
    }

    // MARK: Rotation

    @Test func rotationLandsOnTheNearestStep() {
        #expect(CanvasSnapping.rotationSnap(for: 43) == 45)
        #expect(CanvasSnapping.rotationSnap(for: 92) == 90)
        #expect(CanvasSnapping.rotationSnap(for: -47) == -45)
    }

    @Test func rotationPastTheWindowIsLeftAlone() {
        #expect(CanvasSnapping.rotationSnap(for: 20) == nil)
        #expect(CanvasSnapping.rotationSnap(for: 50) == nil)
    }

    /// The prototype normalised the snapped angle, so 358° found 360 and became
    /// 0 — unwinding a full turn the moment the finger lifted.
    @Test func aLayerTurnedAlmostFullCircleDoesNotUnwind() {
        let snapped = CanvasSnapping.rotationSnap(for: 358)

        #expect(snapped == 360)
        #expect(snapped != 0)
    }

    /// Normalising is for reading, not for storing.
    @Test func theBadgeReadsWholeTurnsBackDown() {
        #expect(CanvasSnapping.readableDegrees(360) == 0)
        #expect(CanvasSnapping.readableDegrees(370) == 10)
        #expect(CanvasSnapping.readableDegrees(-370) == -10)
        #expect(CanvasSnapping.readableDegrees(45) == 45)
    }

    /// Below the tracked threshold the rotation channel is ignored entirely, so
    /// a plain drag cannot nudge a layer askew.
    @Test func aDragDoesNotRotateTheLayerByNoise() {
        let result = snap(rotationDegrees: 12, translation: CGSize(width: 20, height: 0), rotationDelta: 0.1)

        #expect(result.transform.rotationDegrees == 12)
        #expect(result.snappedRotationDegrees == nil)
    }

    // MARK: Scale

    @Test func scaleLandsOnItsTargets() {
        #expect(CanvasSnapping.scaleSnap(for: 0.52) == 0.5)
        #expect(CanvasSnapping.scaleSnap(for: 1.03) == 1)
        #expect(CanvasSnapping.scaleSnap(for: 1.95) == 2)
    }

    /// Each target has its own window, widening with the target.
    @Test func scalePastTheWindowIsLeftAlone() {
        #expect(CanvasSnapping.scaleSnap(for: 0.6) == nil)
        #expect(CanvasSnapping.scaleSnap(for: 1.5) == nil)
        #expect(CanvasSnapping.scaleSnap(for: 3) == nil)
    }

    @Test func aDragDoesNotResizeTheLayerByNoise() {
        let result = snap(scale: 1.7, translation: CGSize(width: 20, height: 0), magnification: 1.001)

        #expect(result.transform.scale == 1.7)
        #expect(result.snappedScale == nil)
    }

    @Test func aPinchStillObeysTheDocumentsScaleRange() {
        let result = snap(scale: 4, magnification: 9)

        #expect(result.transform.scale == ElementTransform.scaleRange.upperBound)
    }

    // MARK: One source for both channels

    /// The guides and what VoiceOver says come from the same value, so they
    /// cannot describe different things.
    @Test func theGuidesAndTheSpokenAlignmentAgree() {
        #expect(CanvasAlignment.centred.showsVerticalLine)
        #expect(CanvasAlignment.centred.showsHorizontalLine)
        #expect(CanvasAlignment.centredHorizontally.showsVerticalLine)
        #expect(!CanvasAlignment.centredHorizontally.showsHorizontalLine)
        #expect(!CanvasAlignment.centredVertically.showsVerticalLine)
        #expect(CanvasAlignment.centredVertically.showsHorizontalLine)
        #expect(!CanvasAlignment.none.showsVerticalLine)
        #expect(!CanvasAlignment.none.showsHorizontalLine)
    }

    /// A guide is drawn exactly when the position was snapped — never one
    /// without the other.
    @Test func aGuideMeansThePositionWasSnapped() {
        let result = snap(from: CGPoint(x: 0.49, y: 0.49), translation: CGSize(width: 1, height: 1))

        #expect(result.alignment == .centred)
        #expect(result.transform.position == CGPoint(x: 0.5, y: 0.5))
    }
}
