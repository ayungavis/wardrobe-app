@preconcurrency import AVFoundation
import Foundation

@MainActor
@Observable
public final class AddByCameraViewModel {
    public enum Phase: Equatable {
        case capturing
        case reviewing
    }

    public private(set) var phase: Phase = .capturing
    public private(set) var permission: CameraPermission = .notDetermined
    public private(set) var isCapturing = false
    public private(set) var capturedCount = 0
    public private(set) var capturedThumbnails: [CGImage] = []
    public private(set) var isFlashOn = false
    public private(set) var isUsingFrontCamera = false
    public private(set) var displayZoomFactor: CGFloat = CameraZoom.standard
    public private(set) var zoomOptions: [CGFloat] = [CameraZoom.standard]
    public var alertError: AppError?

    public let review: GarmentReviewModel

    private let camera: any CameraService
    private var sessionTask: Task<Void, Never>?
    private var captureTask: Task<Void, Never>?
    private var flipTask: Task<Void, Never>?

    public init(camera: any CameraService, review: GarmentReviewModel) {
        self.camera = camera
        self.review = review
    }

    public var previewSession: AVCaptureSession? {
        camera.previewSession
    }

    public func toggleFlash() {
        camera.toggleFlash()
        isFlashOn = camera.isFlashOn
    }

    public func flipCamera() {
        flipTask = Task {
            do {
                try await camera.toggleCamera()
            } catch {
                Log.report(error, logger: Log.ui)
            }
            syncCameraState()
        }
    }

    public func setDisplayZoom(_ factor: CGFloat) {
        camera.setDisplayZoom(CameraZoom.clamp(factor, to: zoomOptions))
        displayZoomFactor = camera.displayZoomFactor
    }

    public func toggleFrontZoom() {
        guard let first = zoomOptions.first, let last = zoomOptions.last, first != last else { return }
        setDisplayZoom(displayZoomFactor >= last ? first : last)
    }

    public func focus(at point: CGPoint) {
        camera.focus(at: point)
    }

    private func syncCameraState() {
        isFlashOn = camera.isFlashOn
        isUsingFrontCamera = camera.isUsingFrontCamera
        zoomOptions = camera.zoomOptions
        displayZoomFactor = camera.displayZoomFactor
    }

    public func onAppear() async {
        permission = camera.permission
        if permission == .notDetermined {
            permission = await camera.requestPermission()
        }
        syncCameraState()
        startSessionIfNeeded()
    }

    public func onDisappear() {
        sessionTask?.cancel()
        captureTask?.cancel()
        camera.stopSession()
    }

    public func sceneBecameActive() {
        guard phase == .capturing, permission != .granted else { return }
        permission = camera.permission
        startSessionIfNeeded()
    }

    public func capture() {
        guard !isCapturing else { return }
        isCapturing = true
        captureTask?.cancel()
        captureTask = Task { [camera, review] in
            defer { isCapturing = false }
            do {
                let photo = try await camera.capturePhoto()
                try Task.checkCancellation()
                review.scan(photo: photo)
                capturedCount += 1
                let thumbnail = await Task.detached(priority: .userInitiated) {
                    ImageDecoding.downsampledImage(from: photo, maxPixel: 160)
                }.value
                try Task.checkCancellation()
                if let thumbnail {
                    capturedThumbnails = Array((capturedThumbnails + [thumbnail]).suffix(3))
                }
            } catch is CancellationError {
            } catch {
                Log.report(error, logger: Log.ui)
                alertError = .captureFailed
            }
        }
    }

    public func beginReview() async {
        sessionTask?.cancel()
        camera.stopSession()
        phase = .reviewing
        await review.finishScanning()
    }

    public func resumeCapturing() {
        capturedCount = 0
        capturedThumbnails = []
        phase = .capturing
        startSessionIfNeeded()
    }

    public func confirm() {
        review.commit(completionID: nil, at: Date())
    }

    public func cancel() {
        captureTask?.cancel()
        review.cancel()
    }

    func settle() async {
        await sessionTask?.value
        await captureTask?.value
        await review.finishScanning()
    }

    private func startSessionIfNeeded() {
        guard permission == .granted else { return }
        sessionTask?.cancel()
        sessionTask = Task {
            do {
                try await camera.startSession()
                // ponytail: the device is only attached inside startSession, so the
                // zoom presets do not exist until it returns.
                syncCameraState()
            } catch is CancellationError {
            } catch {
                Log.report(error, logger: Log.ui)
                alertError = .cameraUnavailable
            }
        }
    }
}
