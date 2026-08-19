import CoreGraphics
import Foundation

enum CanvasAlignment: Equatable {
    case none
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

struct CanvasSnap: Equatable {
    var transform: ElementTransform
    var alignment: CanvasAlignment
    var snappedRotationDegrees: Double?
    var snappedScale: CGFloat?
}

enum CanvasSnapping {
    static let centreThresholdPoints: CGFloat = 8
    static let rotationStep: Double = 45
    static let rotationThresholdDegrees: Double = 4
    static let scaleTargets: [CGFloat] = [0.5, 1, 2]
    static let minimumTrackedRotationDegrees: Double = 0.2
    static let minimumTrackedMagnification: CGFloat = 0.005

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
