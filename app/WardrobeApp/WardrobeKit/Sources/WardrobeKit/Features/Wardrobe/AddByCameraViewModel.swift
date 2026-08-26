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
    public var alertError: AppError?

    public let review: GarmentReviewModel

    private let camera: any CameraService
    private var sessionTask: Task<Void, Never>?
    private var captureTask: Task<Void, Never>?

    public init(camera: any CameraService, review: GarmentReviewModel) {
        self.camera = camera
        self.review = review
    }

    public var previewSession: AVCaptureSession? {
        camera.previewSession
    }

    public func onAppear() async {
        permission = camera.permission
        if permission == .notDetermined {
            permission = await camera.requestPermission()
        }
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
        sessionTask = Task { [camera] in
            do {
                try await camera.startSession()
            } catch is CancellationError {
            } catch {
                Log.report(error, logger: Log.ui)
                alertError = .cameraUnavailable
            }
        }
    }
}
