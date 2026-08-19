import CoreGraphics
import Foundation

/// Turns raw touch points into the three channels a canvas transform needs.
///
/// Deliberately free of UIKit: this is the part that produced the bug where a
/// second finger merely tapping made a layer jump to several times its size, so
/// it is the part that has to be testable without a simulator. What is left in
/// UIKit is a shell that forwards touches here.
///
/// **Contract:** `points` must arrive in a stable order across calls. Touches
/// come from a `Set`, and reordering them would flip the measured angle by 180°
/// — so the recogniser keeps its own ordered list.
struct CanvasTouchTracker: Equatable {
    /// Two fingers closer than this measure a ratio that is mostly noise: at a
    /// 10pt separation a 10pt slip is 2×, which is exactly how a tap came out
    /// as a resize. Until they are this far apart the scale and rotation
    /// channels stay asleep.
    ///
    /// 44pt is §19's touch-target size rather than a number picked to feel
    /// right — the distance below which two fingers are not really two targets.
    static let minimumPinchSeparation: CGFloat = 44

    /// Everything folded in before the current baseline. A finger added or
    /// lifted rebases the measurement, and what was measured until then is
    /// banked here rather than discarded — otherwise the layer would snap back.
    private var settledTranslation: CGSize = .zero
    private var settledMagnification: CGFloat = 1
    private var settledRotation: Double = 0

    private var liveTranslation: CGSize = .zero
    private var liveMagnification: CGFloat = 1
    private var liveRotation: Double = 0

    private var baselineCount = 0
    private var baselineCentroid: CGPoint = .zero
    /// Nil until the fingers are far enough apart to be believed.
    private var baselineSpread: CGFloat?
    private var lastAngle: Double?

    var translation: CGSize {
        CGSize(
            width: settledTranslation.width + liveTranslation.width,
            height: settledTranslation.height + liveTranslation.height
        )
    }

    var magnification: CGFloat {
        settledMagnification * liveMagnification
    }

    var rotationDegrees: Double {
        settledRotation + liveRotation
    }

    mutating func begin(_ points: [CGPoint]) {
        self = CanvasTouchTracker()
        rebaseline(on: points)
    }

    mutating func update(_ points: [CGPoint]) {
        guard !points.isEmpty else { return }

        // A finger arriving or leaving changes what every measurement is
        // relative to. Bank what is measured, then start again from here — so
        // the gesture continues from where it is instead of jumping.
        guard points.count == baselineCount else {
            fold()
            rebaseline(on: points)
            return
        }

        liveTranslation = CGSize(
            width: centroid(points).x - baselineCentroid.x,
            height: centroid(points).y - baselineCentroid.y
        )

        guard points.count >= 2 else { return }
        let spread = spread(points)

        guard let baselineSpread, let lastAngle else {
            // Still asleep. Waking up here rather than at touch-down is what
            // lets a pinch that began too close become usable once the fingers
            // separate, instead of being wrong for its whole life.
            engagePinch(at: points, spread: spread)
            return
        }

        liveMagnification = spread / baselineSpread
        // Accumulated by shortest step rather than compared to the baseline, so
        // turning past half a circle keeps going instead of wrapping backwards.
        let current = angle(points)
        liveRotation += shortestDelta(from: lastAngle, to: current)
        self.lastAngle = current
    }

    private mutating func engagePinch(at points: [CGPoint], spread: CGFloat) {
        guard spread >= Self.minimumPinchSeparation else { return }
        baselineSpread = spread
        lastAngle = angle(points)
    }

    private mutating func fold() {
        settledTranslation = translation
        settledMagnification = magnification
        settledRotation = rotationDegrees
        liveTranslation = .zero
        liveMagnification = 1
        liveRotation = 0
    }

    private mutating func rebaseline(on points: [CGPoint]) {
        baselineCount = points.count
        baselineCentroid = centroid(points)
        baselineSpread = nil
        lastAngle = nil
        guard points.count >= 2 else { return }
        engagePinch(at: points, spread: spread(points))
    }

    private func centroid(_ points: [CGPoint]) -> CGPoint {
        guard !points.isEmpty else { return .zero }
        let count = CGFloat(points.count)
        return CGPoint(
            x: points.reduce(0) { $0 + $1.x } / count,
            y: points.reduce(0) { $0 + $1.y } / count
        )
    }

    /// Mean distance from the centre, doubled so that for two fingers it is
    /// simply the gap between them — which is what `minimumPinchSeparation`
    /// talks about. Generalising past two keeps a third finger from halving the
    /// measurement.
    private func spread(_ points: [CGPoint]) -> CGFloat {
        let centre = centroid(points)
        let total = points.reduce(CGFloat.zero) { sum, point in
            sum + hypot(point.x - centre.x, point.y - centre.y)
        }
        return total / CGFloat(points.count) * 2
    }

    private func angle(_ points: [CGPoint]) -> Double {
        guard let first = points.first, points.count >= 2 else { return 0 }
        let last = points[1]
        return atan2(Double(last.y - first.y), Double(last.x - first.x)) * 180 / .pi
    }

    private func shortestDelta(from: Double, to: Double) -> Double {
        var delta = (to - from).truncatingRemainder(dividingBy: 360)
        if delta > 180 {
            delta -= 360
        } else if delta <= -180 {
            delta += 360
        }
        return delta
    }
}
