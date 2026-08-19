import CoreGraphics
import SwiftUI

/// Attaches the canvas transform recogniser, and on any other platform does
/// nothing. The package also builds for macOS so `swift test` runs without a
/// simulator; the editor exists there only to compile.
///
/// A modifier rather than `#if` inside the canvas's `body`, so the canvas reads
/// as one description of the screen instead of two.
struct CanvasTransformGestureModifier: ViewModifier {
    let onChanged: (CGSize, CGFloat, Double) -> Void
    let onEnded: (CGSize, CGFloat, Double) -> Void
    /// FR-085: an interrupted gesture leaves the document exactly as it was, so
    /// a cancel drops what was measured instead of committing it.
    let onCancelled: () -> Void

    func body(content: Content) -> some View {
        #if os(iOS)
            content.gesture(CanvasTransformGesture(
                onChanged: { onChanged($0.translation, $0.magnification, $0.rotationDegrees) },
                onEnded: { onEnded($0.translation, $0.magnification, $0.rotationDegrees) },
                onCancelled: onCancelled
            ))
        #else
            content
        #endif
    }
}

#if os(iOS)
    import UIKit

    /// Pan, pinch, and rotate as **one** recogniser rather than three.
    ///
    /// One recogniser owns the touch set, so the three channels are measured
    /// from the same fingers and cannot contradict each other — and, unlike
    /// SwiftUI's gestures, it can see where each finger actually is. That is
    /// what makes `CanvasTouchTracker`'s minimum-separation guard possible: the
    /// reason a second finger merely tapping used to resize a layer.
    final class CanvasTransformRecognizer: UIGestureRecognizer {
        /// Matches the 6pt the SwiftUI drag used to ask for, so a press that
        /// never really moves stays a press.
        private static let minimumTranslation: CGFloat = 6

        private var tracker = CanvasTouchTracker()
        /// Ordered, not a `Set`: `CanvasTouchTracker` measures the angle between
        /// the first two points, and a reordering would flip it by 180°.
        private var tracked: [UITouch] = []

        var translation: CGSize {
            tracker.translation
        }

        var magnification: CGFloat {
            tracker.magnification
        }

        var rotationDegrees: Double {
            tracker.rotationDegrees
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            super.touchesBegan(touches, with: event)
            let isFirst = tracked.isEmpty
            for touch in touches where !tracked.contains(touch) {
                tracked.append(touch)
            }
            if isFirst {
                tracker.begin(points())
            } else {
                tracker.update(points())
                advance()
            }
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
            super.touchesMoved(touches, with: event)
            tracker.update(points())
            advance()
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
            super.touchesEnded(touches, with: event)
            finish(touches, endState: .ended)
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
            super.touchesCancelled(touches, with: event)
            finish(touches, endState: .cancelled)
        }

        override func reset() {
            super.reset()
            tracker = CanvasTouchTracker()
            tracked = []
        }

        private func finish(_ touches: Set<UITouch>, endState: UIGestureRecognizer.State) {
            tracked.removeAll { touches.contains($0) }
            guard tracked.isEmpty else {
                // Fingers remain: the tracker rebases on the new count, and the
                // gesture carries on rather than committing half-way.
                tracker.update(points())
                advance()
                return
            }
            // Never having started means nothing to report — a tap that fell
            // through here must not commit a transform.
            state = state == .possible ? .failed : endState
        }

        /// Stays `.possible` until something worth acting on has happened, so a
        /// stationary press is left to the layer's own tap and press handling.
        private func advance() {
            guard state != .possible else {
                if hasMovedEnough {
                    state = .began
                }
                return
            }
            state = .changed
        }

        private var hasMovedEnough: Bool {
            hypot(tracker.translation.width, tracker.translation.height) >= Self.minimumTranslation
                || tracker.magnification != 1
                || tracker.rotationDegrees != 0
        }

        private func points() -> [CGPoint] {
            tracked.map { $0.location(in: view) }
        }
    }

    /// Bridges the recogniser into SwiftUI's own gesture arbitration, so the
    /// per-layer taps and press tracking underneath keep working.
    struct CanvasTransformGesture: UIGestureRecognizerRepresentable {
        let onChanged: (CanvasTransformRecognizer) -> Void
        let onEnded: (CanvasTransformRecognizer) -> Void
        let onCancelled: () -> Void

        func makeUIGestureRecognizer(context: Context) -> CanvasTransformRecognizer {
            let recognizer = CanvasTransformRecognizer()
            // The layers below still own selection and reopening; this
            // recogniser must observe the same touches, not consume them.
            recognizer.cancelsTouchesInView = false
            recognizer.delaysTouchesBegan = false
            recognizer.delegate = context.coordinator
            return recognizer
        }

        func updateUIGestureRecognizer(_: CanvasTransformRecognizer, context _: Context) {}

        func handleUIGestureRecognizerAction(_ recognizer: CanvasTransformRecognizer, context _: Context) {
            switch recognizer.state {
            case .began, .changed:
                onChanged(recognizer)
            case .ended:
                onEnded(recognizer)
            case .cancelled, .failed:
                onCancelled()
            default:
                break
            }
        }

        func makeCoordinator(converter _: CoordinateSpaceConverter) -> Coordinator {
            Coordinator()
        }

        final class Coordinator: NSObject, UIGestureRecognizerDelegate {
            func gestureRecognizer(
                _: UIGestureRecognizer,
                shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer
            ) -> Bool {
                true
            }
        }
    }
#endif
