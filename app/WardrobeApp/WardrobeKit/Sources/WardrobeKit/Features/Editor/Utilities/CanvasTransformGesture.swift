import CoreGraphics
import SwiftUI

struct CanvasTransformGestureModifier: ViewModifier {
    /// The canvas declares this space and the recogniser converts into it.
    /// SwiftUI makes no `UIView` per view, so a touch's `location(in: view)`
    /// lands in a shared host's space, not the canvas's — offset by wherever
    /// the canvas sits on screen.
    static let coordinateSpace = "editorCanvas"

    /// Which layer the first finger landed on, and what the fingers have done
    /// since. One report rather than two pieces of state kept in step: sharing
    /// the held layer between SwiftUI and UIKit is what let a second finger
    /// cancel it mid-gesture.
    struct Update {
        let layerID: UUID
        let translation: CGSize
        let magnification: CGFloat
        let rotationDegrees: Double
    }

    let hitTest: (CGPoint) -> UUID?
    let onChanged: (Update) -> Void
    let onEnded: (Update) -> Void
    let onCancelled: () -> Void

    func body(content: Content) -> some View {
        #if os(iOS)
            content.gesture(CanvasTransformGesture(
                hitTest: hitTest,
                onChanged: { report($0).map(onChanged) },
                onEnded: { report($0).map(onEnded) },
                onCancelled: onCancelled
            ))
        #else
            content
        #endif
    }

    #if os(iOS)
        private func report(_ recognizer: CanvasTransformRecognizer) -> Update? {
            guard let layerID = recognizer.heldLayerID else { return nil }
            return Update(
                layerID: layerID,
                translation: recognizer.translation,
                magnification: recognizer.magnification,
                rotationDegrees: recognizer.rotationDegrees
            )
        }
    #endif
}

#if os(iOS)
    import UIKit

    final class CanvasTransformRecognizer: UIGestureRecognizer {
        private static let minimumTranslation: CGFloat = 6

        /// Decides the layer on the first touch and never again — "the first
        /// finger wins" as structure rather than as a guard somewhere else.
        /// Takes a point in **window** coordinates; the representable converts
        /// it into the canvas's space before the hit test sees it.
        var hitTest: (CGPoint) -> UUID? = { _ in nil }
        private(set) var heldLayerID: UUID?

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
                heldLayerID = touches.first.map { hitTest($0.location(in: nil)) } ?? nil
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
            heldLayerID = nil
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
        let hitTest: (CGPoint) -> UUID?
        let onChanged: (CanvasTransformRecognizer) -> Void
        let onEnded: (CanvasTransformRecognizer) -> Void
        let onCancelled: () -> Void

        func makeUIGestureRecognizer(context: Context) -> CanvasTransformRecognizer {
            let recognizer = CanvasTransformRecognizer()
            recognizer.cancelsTouchesInView = false
            recognizer.delaysTouchesBegan = false
            recognizer.delegate = context.coordinator
            install(hitTest, on: recognizer, converter: context.converter)
            return recognizer
        }

        /// Refreshed every update so the hit test sees the current document,
        /// canvas size, and open tool.
        func updateUIGestureRecognizer(_ recognizer: CanvasTransformRecognizer, context: Context) {
            install(hitTest, on: recognizer, converter: context.converter)
        }

        /// SwiftUI does the conversion rather than arithmetic of ours against a
        /// recorded frame: that would only hold if `.global` and the window's
        /// coordinates always agreed, and this asks the framework instead.
        private func install(
            _ hitTest: @escaping (CGPoint) -> UUID?,
            on recognizer: CanvasTransformRecognizer,
            converter: CoordinateSpaceConverter
        ) {
            recognizer.hitTest = { windowPoint in
                hitTest(converter.convert(
                    globalPoint: windowPoint,
                    to: .named(CanvasTransformGestureModifier.coordinateSpace)
                ))
            }
        }

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
