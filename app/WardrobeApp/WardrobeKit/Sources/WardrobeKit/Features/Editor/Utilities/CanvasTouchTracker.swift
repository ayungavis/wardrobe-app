import CoreGraphics
import Foundation

/// Free of UIKit so it can be tested without a simulator — this is the part that
/// produced the bug where a second finger merely tapping resized a layer.
///
/// **Contract:** `points` must arrive in a stable order across calls; reordering
/// them would flip the measured angle by 180°.
struct CanvasTouchTracker: Equatable {
    /// Below this the ratio is mostly noise: at a 10pt separation a 10pt slip is
    /// 2×, which is exactly how a tap came out as a resize. 44pt is §19's
    /// touch-target size, not a number picked to feel right.
    static let minimumPinchSeparation: CGFloat = 44

    private var settledTranslation: CGSize = .zero
    private var settledMagnification: CGFloat = 1
    private var settledRotation: Double = 0

    private var liveTranslation: CGSize = .zero
    private var liveMagnification: CGFloat = 1
    private var liveRotation: Double = 0

    private var baselineCount = 0
    private var baselineCentroid: CGPoint = .zero
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
            engagePinch(at: points, spread: spread)
            return
        }

        liveMagnification = spread / baselineSpread
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
