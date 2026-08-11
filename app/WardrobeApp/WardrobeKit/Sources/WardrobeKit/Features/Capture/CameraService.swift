@preconcurrency import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum CameraPermission: Equatable, Sendable {
    case notDetermined
    case granted
    case denied
    case restricted
}

@MainActor
public protocol CameraService: AnyObject {
    /// Current authorization state — re-read on every access (FR-014).
    var permission: CameraPermission { get }
    /// Non-nil only for a real device camera; drives the live preview layer.
    var previewSession: AVCaptureSession? { get }
    var isFlashOn: Bool { get }
    /// Current optical/digital zoom; 1 is the unzoomed framing.
    var zoomFactor: CGFloat { get }
    func requestPermission() async -> CameraPermission
    func startSession() async throws
    func stopSession()
    /// Switches between back and front camera. No-op where unsupported.
    func toggleCamera() async throws
    func toggleFlash()
    /// Clamped by the implementation to what the device supports.
    func setZoom(_ factor: CGFloat)
    /// Focus + expose on a point in unit preview space (0...1).
    func focus(at point: CGPoint)
    /// Returns JPEG data. Throws `AppError.captureFailed`.
    func capturePhoto() async throws -> Data
}

/// Shared zoom ceiling — plenty for framing an outfit, and keeps the sample
/// service and the real device in step.
enum CameraZoom {
    static let minFactor: CGFloat = 1
    static let maxFactor: CGFloat = 5

    static func clamp(_ factor: CGFloat, deviceMax: CGFloat = maxFactor) -> CGFloat {
        min(min(maxFactor, deviceMax), max(minFactor, factor))
    }
}

/// Camera stand-in for the simulator, macOS, previews, and tests — generates
/// a solid-color JPEG so the full flow works without camera hardware.
@MainActor
public final class SampleCameraService: CameraService {
    public private(set) var permission: CameraPermission = .notDetermined
    public var previewSession: AVCaptureSession? {
        nil
    }

    public init() {
        #if DEBUG
            // UI-verification seam: skip the consent stage in scripted runs.
            if ProcessInfo.processInfo.arguments.contains("-cameraGranted") {
                permission = .granted
            }
        #endif
    }

    public func requestPermission() async -> CameraPermission {
        permission = .granted
        return permission
    }

    public private(set) var isFlashOn = false
    public private(set) var zoomFactor: CGFloat = CameraZoom.minFactor
    /// Last focus request — no hardware to drive, but keeps the flow honest.
    public private(set) var lastFocusPoint: CGPoint?

    public func startSession() async throws {}
    public func stopSession() {}
    public func toggleCamera() async throws {}
    public func toggleFlash() {
        isFlashOn.toggle()
    }

    public func setZoom(_ factor: CGFloat) {
        zoomFactor = CameraZoom.clamp(factor)
    }

    public func focus(at point: CGPoint) {
        lastFocusPoint = point
    }

    public func capturePhoto() async throws -> Data {
        try Self.makeSampleJPEG()
    }

    static func makeSampleJPEG(width: Int = 1080, height: Int = 1920) throws -> Data {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { throw AppError.captureFailed }

        ctx.setFillColor(CGColor(srgbRed: 0.345, green: 0.337, blue: 0.839, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: width / 4, y: height / 3, width: width / 2, height: width / 2))

        guard let image = ctx.makeImage() else { throw AppError.captureFailed }

        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw AppError.captureFailed
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw AppError.captureFailed }
        return out as Data
    }
}
