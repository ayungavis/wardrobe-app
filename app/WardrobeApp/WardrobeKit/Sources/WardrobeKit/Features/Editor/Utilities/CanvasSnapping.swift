import CoreGraphics
import Foundation

/// Where a layer sits relative to the canvas's centre lines.
///
/// One value serves both channels FR-089 needs: it decides which guide lines
/// are drawn, and it is what VoiceOver is told. They cannot disagree because
/// there is only one of them.
enum CanvasAlignment: Equatable {
    case none
    /// Centred left-to-right — the guide drawn for it is a vertical line.
    case centredHorizontally
    case centredVertically
    case centred

    var showsVerticalLine: Bool {
        self == .centredHorizontally || self == .centred
    }

    var showsHorizontalLine: Bool {
        self == .centredVertically || self == .centred
    }
}

/// One evaluation of a gesture: where the layer should go, and what the canvas
/// should say about it.
struct CanvasSnap: Equatable {
    var transform: ElementTransform
    var alignment: CanvasAlignment
    /// Set only when rotation actually landed on a step — the badge shows it.
    var snappedRotationDegrees: Double?
    var snappedScale: CGFloat?
}

/// Advisory adjustment during a transform (FR-089).
///
/// Advisory is the operative word: outside its windows every value passes
/// through untouched, so a transform can always be continued when no guide
/// applies.
enum CanvasSnapping {
    /// Kept in points rather than a fraction of the canvas. Finger precision is
    /// physical, so an 8pt window feels the same on every device — where a
    /// fraction would be a wider capture on a small screen.
    static let centreThresholdPoints: CGFloat = 8
    static let rotationStep: Double = 45
    static let rotationThresholdDegrees: Double = 4
    static let scaleTargets: [CGFloat] = [0.5, 1, 2]
    /// Below these a gesture channel is treated as untouched, which is what
    /// stops a drag from nudging scale or rotation by pinch noise.
    static let minimumTrackedRotationDegrees: Double = 0.2
    static let minimumTrackedMagnification: CGFloat = 0.005

    /// The one composition of a gesture into a transform.
    ///
    /// Both the drawn transform and the committed one call this, so what you
    /// see during the drag is exactly what gets stored.
    static func snap(
        committed: ElementTransform,
        translation: CGSize,
        magnification: CGFloat,
        rotationDelta: Double,
        canvasSize: CGSize
    ) -> CanvasSnap {
        let isTranslating = translation != .zero
        let isMagnifying = abs(magnification - 1) >= minimumTrackedMagnification
        let isRotating = abs(rotationDelta) >= minimumTrackedRotationDegrees

        let proposed = CanvasGeometry.position(
            committed.position, translatedBy: translation, in: canvasSize
        )
        // Position only snaps while the layer is actually being moved. The
        // prototype snapped on any interaction, so a layer parked a few points
        // off centre jumped there the moment it was pinched.
        let alignment = isTranslating ? alignment(of: proposed, in: canvasSize) : .none
        let position = CGPoint(
            x: alignment.showsVerticalLine ? 0.5 : proposed.x,
            y: alignment.showsHorizontalLine ? 0.5 : proposed.y
        )

        var snappedRotation: Double?
        var rotation = committed.rotationDegrees
        if isRotating {
            let proposedRotation = committed.rotationDegrees + rotationDelta
            snappedRotation = rotationSnap(for: proposedRotation)
            rotation = snappedRotation ?? proposedRotation
        }

        var snappedScaleTarget: CGFloat?
        var scale = committed.scale
        if isMagnifying {
            let proposedScale = ElementTransform.clampedScale(committed.scale * magnification)
            snappedScaleTarget = scaleSnap(for: proposedScale)
            scale = snappedScaleTarget ?? proposedScale
        }

        return CanvasSnap(
            transform: ElementTransform(
                position: position, scale: scale, rotationDegrees: rotation
            ),
            alignment: alignment,
            snappedRotationDegrees: snappedRotation,
            snappedScale: snappedScaleTarget
        )
    }

    /// Which centre lines a position sits on. Read by the guides, by the snap,
    /// and by what VoiceOver reads out.
    static func alignment(of position: CGPoint, in canvasSize: CGSize) -> CanvasAlignment {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return .none }

        let onVertical = abs(position.x - 0.5) <= centreThresholdPoints / canvasSize.width
        let onHorizontal = abs(position.y - 0.5) <= centreThresholdPoints / canvasSize.height

        switch (onVertical, onHorizontal) {
        case (true, true): return .centred
        case (true, false): return .centredHorizontally
        case (false, true): return .centredVertically
        case (false, false): return .none
        }
    }

    /// The nearest step, **unnormalised**.
    ///
    /// Normalising here is the prototype's bug: at 358° the nearest step is
    /// 360, which normalised to 0 and unwound the layer a whole turn on commit.
    /// Only the badge normalises, and only to read it out.
    static func rotationSnap(for degrees: Double) -> Double? {
        let nearest = (degrees / rotationStep).rounded() * rotationStep
        guard abs(degrees - nearest) <= rotationThresholdDegrees else { return nil }
        return nearest
    }

    static func scaleSnap(for scale: CGFloat) -> CGFloat? {
        guard let target = scaleTargets.min(by: { abs($0 - scale) < abs($1 - scale) }) else {
            return nil
        }
        guard abs(scale - target) <= max(0.035, target * 0.04) else { return nil }
        return target
    }

    /// Turns whole turns back into something a person can read: 370° is 10°.
    static func readableDegrees(_ degrees: Double) -> Int {
        var value = degrees.truncatingRemainder(dividingBy: 360)
        if value > 180 {
            value -= 360
        } else if value <= -180 {
            value += 360
        }
        return Int(value.rounded())
    }
}
