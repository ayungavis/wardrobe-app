@preconcurrency import AVFoundation
import CoreGraphics
import Foundation

@MainActor
public protocol CameraService: AnyObject {
    /// Current authorization state — re-read on every access (FR-014).
    var permission: CameraPermission { get }
    /// Non-nil only for a real device camera; drives the live preview layer.
    var previewSession: AVCaptureSession? { get }
    var isFlashOn: Bool { get }
    var isUsingFrontCamera: Bool { get }
    /// Zoom as the user sees it: 1 is the standard lens, 0.5 ultra-wide.
    /// The service maps this onto the device's own zoom scale.
    var displayZoomFactor: CGFloat { get }
    /// Preset factors this device can actually reach, ascending.
    var zoomOptions: [CGFloat] { get }
    func requestPermission() async -> CameraPermission
    func startSession() async throws
    func stopSession()
    /// Switches between back and front camera. No-op where unsupported.
    func toggleCamera() async throws
    func toggleFlash()
    /// Clamped by the implementation to what the device supports.
    func setDisplayZoom(_ factor: CGFloat)
    /// Focus + expose on a point in unit preview space (0...1).
    func focus(at point: CGPoint)
    /// Returns JPEG data. Throws `AppError.captureFailed`.
    func capturePhoto() async throws -> Data
}
