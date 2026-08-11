@preconcurrency import AVFoundation
import Foundation
import Observation

public enum CaptureStage: Equatable {
    case consent
    case denied
    case camera
    case editor
}

@MainActor
@Observable
public final class CaptureFlowViewModel {
    public private(set) var stage: CaptureStage
    public private(set) var challenge: ActiveChallenge
    public var alertError: AppError?
    public private(set) var isCapturing = false
    /// Mirrored from the camera service so the view observes changes.
    public private(set) var isFlashOn = false
    public private(set) var zoomFactor: CGFloat = CameraZoom.minFactor
    /// Latest tap-to-focus point in unit preview space, for the indicator.
    public private(set) var focusPoint: CGPoint?

    private let camera: CameraService
    private let store: ActiveChallengeStore
    private let photoStore: PhotoStore
    private(set) var consentTask: Task<Void, Never>?
    private(set) var captureTask: Task<Void, Never>?
    private(set) var sessionTask: Task<Void, Never>?
    private(set) var flipTask: Task<Void, Never>?

    public init(
        challenge: ActiveChallenge,
        camera: CameraService,
        store: ActiveChallengeStore,
        photoStore: PhotoStore
    ) {
        self.challenge = challenge
        self.camera = camera
        self.store = store
        self.photoStore = photoStore
        stage = Self.initialStage(challenge: challenge, permission: camera.permission)
    }

    static func initialStage(challenge: ActiveChallenge, permission: CameraPermission) -> CaptureStage {
        if challenge.photoID != nil {
            return .editor
        } // resume straight to editor (FR-017)
        switch permission {
        case .granted: return .camera
        case .notDetermined: return .consent // FR-013: explain before the system prompt
        case .denied, .restricted: return .denied
        }
    }

    // MARK: Consent / permission (FR-013, FR-014)

    public func consentContinue() {
        consentTask = Task {
            let result = await camera.requestPermission()
            stage = result == .granted ? .camera : .denied
        }
    }

    /// Re-check on foreground — covers returning from Settings after a grant
    /// or revocation. Only pre-photo stages are recomputed.
    public func recheckPermission() {
        switch stage {
        case .consent, .denied, .camera:
            stage = Self.initialStage(challenge: challenge, permission: camera.permission)
        case .editor:
            break
        }
    }

    // MARK: Camera session (FR-015)

    public func cameraAppeared() {
        sessionTask?.cancel()
        sessionTask = Task {
            do {
                try await camera.startSession()
            } catch is CancellationError {
                // Ignore cancellation.
            } catch {
                Log.report(error, logger: Log.ui)
                alertError = .cameraUnavailable
            }
        }
    }

    public func cameraDisappeared() {
        sessionTask?.cancel()
        camera.stopSession()
    }

    public func flipCamera() {
        flipTask = Task {
            do {
                try await camera.toggleCamera()
            } catch {
                Log.report(error, logger: Log.ui) // non-fatal: stay on the current camera
            }
        }
    }

    public var previewSession: AVCaptureSession? {
        camera.previewSession
    }

    // MARK: Capture (FR-016)

    /// Story-style: a successful shutter goes straight to the editor
    /// (the editor is the preview; discarding is the retake — FR-016).
    public func capture() {
        guard !isCapturing else { return }
        isCapturing = true

        captureTask = Task {
            defer { isCapturing = false }
            let start = ContinuousClock.now
            do {
                let data = try await camera.capturePhoto()
                try Task.checkCancellation()
                Log.ui.info("Capture finished in \((ContinuousClock.now - start).ms, privacy: .public)ms")
                persistPhoto(data)
            } catch is CancellationError {
                // Ignore cancellation.
            } catch {
                Log.report(error, logger: Log.ui)
                alertError = .captureFailed // stay in .camera; no photo record
            }
        }
    }

    public func toggleFlash() {
        camera.toggleFlash()
        isFlashOn = camera.isFlashOn
    }

    /// Pinch-to-zoom. The service clamps; we mirror what it accepted.
    public func setZoom(_ factor: CGFloat) {
        camera.setZoom(factor)
        zoomFactor = camera.zoomFactor
    }

    /// Tap-to-focus. `point` is in unit preview space (0...1).
    public func focus(at point: CGPoint) {
        camera.focus(at: point)
        focusPoint = point
    }

    /// Ordering matters: file write first, then persist photoID, then editor.
    /// A failed write leaves nothing persisted (FR-016).
    private func persistPhoto(_ data: Data) {
        do {
            let id = try photoStore.saveOriginal(data)
            challenge.photoID = id
            store.save(challenge)
            stage = .editor
        } catch {
            Log.report(error)
            alertError = .captureFailed
        }
    }

    /// Editor X: throw the photo and its edits away, back to the camera.
    public func discardPhoto() {
        if let photoID = challenge.photoID {
            do {
                try photoStore.deleteOriginal(id: photoID)
            } catch {
                Log.report(error) // orphaned file is not worth blocking the retake
            }
        }
        challenge.photoID = nil
        challenge.draft = EditDraft()
        store.save(challenge)
        stage = .camera
    }
}

extension Duration {
    var ms: Int {
        Int(components.seconds * 1000) + Int(components.attoseconds / 1_000_000_000_000_000)
    }
}
