@preconcurrency import AVFoundation
import CoreGraphics
import Foundation

@MainActor
public protocol CameraService: AnyObject {
    var permission: CameraPermission { get }
    var previewSession: AVCaptureSession? { get }
    var isFlashOn: Bool { get }
    var isUsingFrontCamera: Bool { get }
    var displayZoomFactor: CGFloat { get }
    var zoomOptions: [CGFloat] { get }
    func requestPermission() async -> CameraPermission
    func startSession() async throws
    func stopSession()
    func toggleCamera() async throws
    func toggleFlash()
    func setDisplayZoom(_ factor: CGFloat)
    func focus(at point: CGPoint)
    func capturePhoto() async throws -> Data
}
