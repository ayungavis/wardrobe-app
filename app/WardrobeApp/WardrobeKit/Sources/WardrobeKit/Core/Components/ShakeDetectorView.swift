#if os(iOS)
    import SwiftUI
    import UIKit

    struct ShakeDetectorView: UIViewRepresentable {
        let onShake: () -> Void

        func makeUIView(context _: Context) -> Responder {
            let responder = Responder()
            responder.onShake = onShake
            return responder
        }

        func updateUIView(_ uiView: Responder, context _: Context) {
            uiView.onShake = onShake
            if !uiView.isFirstResponder {
                uiView.becomeFirstResponder()
            }
        }

        final class Responder: UIView {
            var onShake: (() -> Void)?

            override var canBecomeFirstResponder: Bool {
                true
            }

            override func didMoveToWindow() {
                super.didMoveToWindow()
                becomeFirstResponder()
            }

            // ponytail: a motion event reaches the first responder and then climbs the
            // chain, so a focused text field elsewhere swallows the shake. Hook the
            // window instead if that ever starts mattering.
            override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
                guard motion == .motionShake else {
                    super.motionEnded(motion, with: event)
                    return
                }
                onShake?()
            }
        }
    }
#endif
