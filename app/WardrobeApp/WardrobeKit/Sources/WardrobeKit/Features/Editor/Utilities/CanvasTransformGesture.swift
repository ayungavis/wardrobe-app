import CoreGraphics
import SwiftUI

struct CanvasTransformGestureModifier: ViewModifier {
    let onChanged: (CGSize, CGFloat, Double) -> Void
    let onEnded: (CGSize, CGFloat, Double) -> Void
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

    final class CanvasTransformRecognizer: UIGestureRecognizer {
        private static let minimumTranslation: CGFloat = 6

        private var tracker = CanvasTouchTracker()
        /// Ordered, not a `Set`: reordering would flip the measured angle by 180°.
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
                tracker.update(points())
                advance()
                return
            }
            state = state == .possible ? .failed : endState
        }

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

    struct CanvasTransformGesture: UIGestureRecognizerRepresentable {
        let onChanged: (CanvasTransformRecognizer) -> Void
        let onEnded: (CanvasTransformRecognizer) -> Void
        let onCancelled: () -> Void

        func makeUIGestureRecognizer(context: Context) -> CanvasTransformRecognizer {
            let recognizer = CanvasTransformRecognizer()
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
