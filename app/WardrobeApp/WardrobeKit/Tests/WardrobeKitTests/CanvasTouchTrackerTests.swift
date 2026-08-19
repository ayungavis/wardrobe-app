import CoreGraphics
import Testing
@testable import WardrobeKit

/// The maths behind the canvas transform. It lives apart from UIKit precisely
/// so this suite can exist — the resize-from-a-tap bug was arithmetic, not
/// plumbing, and arithmetic can be pinned down without a simulator.
struct CanvasTouchTrackerTests {
    private let gap = CanvasTouchTracker.minimumPinchSeparation

    @Test func oneFingerOnlyTranslates() {
        var sut = CanvasTouchTracker()
        sut.begin([CGPoint(x: 100, y: 100)])

        sut.update([CGPoint(x: 140, y: 90)])

        #expect(sut.translation == CGSize(width: 40, height: -10))
        #expect(sut.magnification == 1)
        #expect(sut.rotationDegrees == 0)
    }

    @Test func twoFingersSpreadingScaleUp() {
        var sut = CanvasTouchTracker()
        sut.begin([CGPoint(x: 100, y: 100), CGPoint(x: 100 + gap, y: 100)])

        sut.update([CGPoint(x: 100, y: 100), CGPoint(x: 100 + gap * 2, y: 100)])

        #expect(abs(sut.magnification - 2) < 0.001)
    }

    @Test func twoFingersTurningRotate() {
        var sut = CanvasTouchTracker()
        sut.begin([CGPoint(x: 0, y: 0), CGPoint(x: gap, y: 0)])

        sut.update([CGPoint(x: 0, y: 0), CGPoint(x: 0, y: gap)])

        #expect(abs(sut.rotationDegrees - 90) < 0.001)
    }

    /// The reported bug. A second finger landing close by and lifting again is
    /// a tap, not a pinch — and a tap must not resize anything.
    @Test func aSecondFingerTappingCloseByDoesNotScale() {
        var sut = CanvasTouchTracker()
        sut.begin([CGPoint(x: 100, y: 100)])

        // Lands 10pt away — far below the separation a ratio can be trusted at.
        sut.update([CGPoint(x: 100, y: 100), CGPoint(x: 110, y: 100)])
        // Both fingers wobble a little, as fingers do.
        sut.update([CGPoint(x: 103, y: 101), CGPoint(x: 118, y: 99)])
        // And it lifts again.
        sut.update([CGPoint(x: 103, y: 101)])

        #expect(sut.magnification == 1)
        #expect(sut.rotationDegrees == 0)
    }

    /// Same guard, stated directly: below the threshold the channel is asleep,
    /// and it wakes only once the fingers are genuinely apart.
    @Test func theScaleChannelWakesOnlyOnceTheFingersSeparate() {
        var sut = CanvasTouchTracker()
        sut.begin([CGPoint(x: 100, y: 100), CGPoint(x: 110, y: 100)])

        sut.update([CGPoint(x: 100, y: 100), CGPoint(x: 130, y: 100)])
        #expect(sut.magnification == 1, "still closer than the minimum")

        // Crosses the threshold: this separation becomes the reference, so
        // nothing jumps at the moment it engages.
        sut.update([CGPoint(x: 100, y: 100), CGPoint(x: 100 + gap, y: 100)])
        #expect(sut.magnification == 1)

        sut.update([CGPoint(x: 100, y: 100), CGPoint(x: 100 + gap * 2, y: 100)])
        #expect(abs(sut.magnification - 2) < 0.001)
    }

    /// Adding a finger mid-gesture rebases every measurement. What was measured
    /// until then is banked, so the layer carries on from where it is.
    @Test func addingAFingerKeepsWhatWasAlreadyMeasured() {
        var sut = CanvasTouchTracker()
        sut.begin([CGPoint(x: 100, y: 100), CGPoint(x: 100 + gap, y: 100)])
        sut.update([CGPoint(x: 100, y: 100), CGPoint(x: 100 + gap * 2, y: 100)])
        let beforeThirdFinger = sut.magnification

        sut.update([CGPoint(x: 100, y: 100), CGPoint(x: 100 + gap * 2, y: 100), CGPoint(x: 100, y: 200)])

        #expect(sut.magnification == beforeThirdFinger, "a new finger must not resize anything by itself")
    }

    /// And lifting one back off must not jump either — the case that reads as
    /// the layer suddenly springing to a different size.
    @Test func liftingAFingerDoesNotJump() {
        var sut = CanvasTouchTracker()
        sut.begin([CGPoint(x: 100, y: 100), CGPoint(x: 100 + gap, y: 100)])
        sut.update([CGPoint(x: 100, y: 100), CGPoint(x: 100 + gap * 2, y: 100)])
        let magnification = sut.magnification
        let translation = sut.translation
        let rotation = sut.rotationDegrees

        sut.update([CGPoint(x: 100, y: 100)])

        #expect(sut.magnification == magnification)
        #expect(sut.translation == translation)
        #expect(sut.rotationDegrees == rotation)
    }

    /// Turning past half a circle has to keep counting up rather than wrapping
    /// back — otherwise a layer spun a long way snaps round on release.
    @Test func rotationAccumulatesPastHalfATurn() {
        var sut = CanvasTouchTracker()
        sut.begin([CGPoint(x: 0, y: 0), CGPoint(x: gap, y: 0)])

        for degrees in stride(from: 45.0, through: 270.0, by: 45.0) {
            let radians = degrees * .pi / 180
            sut.update([CGPoint(x: 0, y: 0), CGPoint(x: cos(radians) * gap, y: sin(radians) * gap)])
        }

        #expect(abs(sut.rotationDegrees - 270) < 0.001)
    }

    @Test func beginResetsEverythingFromAPreviousGesture() {
        var sut = CanvasTouchTracker()
        sut.begin([CGPoint(x: 0, y: 0), CGPoint(x: gap, y: 0)])
        sut.update([CGPoint(x: 0, y: 0), CGPoint(x: gap * 3, y: 0)])

        sut.begin([CGPoint(x: 50, y: 50)])

        #expect(sut.translation == .zero)
        #expect(sut.magnification == 1)
        #expect(sut.rotationDegrees == 0)
    }
}
