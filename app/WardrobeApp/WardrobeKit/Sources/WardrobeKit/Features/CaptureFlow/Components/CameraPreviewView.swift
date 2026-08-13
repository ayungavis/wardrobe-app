#if os(iOS)
    @preconcurrency import AVFoundation
    import SwiftUI

    /// Live camera feed. UIKit bridge is confined to this file.
    struct CameraPreviewView: UIViewRepresentable {
        let session: AVCaptureSession

        final class PreviewUIView: UIView {
            override static var layerClass: AnyClass {
                AVCaptureVideoPreviewLayer.self
            }

            var previewLayer: AVCaptureVideoPreviewLayer {
                guard let layer = layer as? AVCaptureVideoPreviewLayer else {
                    fatalError("layerClass is AVCaptureVideoPreviewLayer")
                }
                return layer
            }
        }

        func makeUIView(context _: Context) -> PreviewUIView {
            let view = PreviewUIView()
            view.previewLayer.session = session
            view.previewLayer.videoGravity = .resizeAspectFill
            return view
        }

        func updateUIView(_: PreviewUIView, context _: Context) {}
    }
#endif
