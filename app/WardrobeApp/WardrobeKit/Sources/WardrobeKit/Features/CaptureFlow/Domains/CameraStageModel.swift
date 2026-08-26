import AVFoundation
import CoreGraphics

@MainActor
public protocol CameraStageModel: AnyObject {
    var previewSession: AVCaptureSession? { get }
    var displayZoomFactor: CGFloat { get }
    var zoomOptions: [CGFloat] { get }
    var isUsingFrontCamera: Bool { get }
    func setDisplayZoom(_ factor: CGFloat)
    func toggleFrontZoom()
    func focus(at point: CGPoint)
}

extension CaptureFlowViewModel: CameraStageModel {}

extension AddByCameraViewModel: CameraStageModel {}
