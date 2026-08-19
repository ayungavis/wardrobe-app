@preconcurrency import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

@MainActor
public final class SampleCameraService: CameraService {
    public private(set) var permission: CameraPermission = .notDetermined
    public var previewSession: AVCaptureSession? {
        nil
    }

    public init() {
        #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("-cameraGranted") {
                permission = .granted
            }
            if arguments.contains("-frontCamera") {
                isUsingFrontCamera = true
            }
        #endif
    }

    public func requestPermission() async -> CameraPermission {
        permission = .granted
        return permission
    }

    public private(set) var isFlashOn = false
    public private(set) var isUsingFrontCamera = false
    public private(set) var displayZoomFactor: CGFloat = CameraZoom.standard
    public private(set) var lastFocusPoint: CGPoint?

    public var zoomOptions: [CGFloat] {
        isUsingFrontCamera ? [1, 2] : CameraZoom.presets
    }

    public func startSession() async throws {}
    public func stopSession() {}

    public func toggleCamera() async throws {
        isUsingFrontCamera.toggle()
        displayZoomFactor = CameraZoom.standard
    }

    public func toggleFlash() {
        isFlashOn.toggle()
    }

    public func setDisplayZoom(_ factor: CGFloat) {
        displayZoomFactor = CameraZoom.clamp(factor, to: zoomOptions)
    }

    public func focus(at point: CGPoint) {
        lastFocusPoint = point
    }

    public func capturePhoto() async throws -> Data {
        try Self.makeSampleJPEG()
    }

    static func makeSampleJPEG(width: Int = 1080, height: Int = 1920) throws -> Data {
        let cs = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
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
