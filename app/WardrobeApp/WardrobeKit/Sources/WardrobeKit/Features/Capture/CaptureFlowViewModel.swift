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
    public private(set) var isUsingFrontCamera = false
    public private(set) var displayZoomFactor: CGFloat = CameraZoom.standard
    public private(set) var zoomOptions: [CGFloat] = [CameraZoom.standard]
    /// Latest tap-to-focus point in unit preview space, for the indicator.
    public private(set) var focusPoint: CGPoint?
    /// Newest library photo for the gallery button; nil when unavailable.
    public private(set) var galleryThumbnail: CGImage?
    public private(set) var libraryAccess: PhotoLibraryAccess = .notDetermined
    public private(set) var recentAssets: [PhotoAsset] = []
    public var isGalleryPresented = false

    /// Grid cells load their own thumbnails straight from the browser, so a
    /// thumbnail arriving never invalidates the whole grid.
    public let library: PhotoLibraryBrowsing

    private let camera: CameraService
    private let store: ActiveChallengeStore
    private let photoStore: PhotoStore
    private(set) var consentTask: Task<Void, Never>?
    private(set) var captureTask: Task<Void, Never>?
    private(set) var sessionTask: Task<Void, Never>?
    private(set) var flipTask: Task<Void, Never>?
    private(set) var importTask: Task<Void, Never>?
    private(set) var thumbnailTask: Task<Void, Never>?

    public init(
        challenge: ActiveChallenge,
        camera: CameraService,
        store: ActiveChallengeStore,
        photoStore: PhotoStore,
        library: PhotoLibraryBrowsing
    ) {
        self.challenge = challenge
        self.camera = camera
        self.store = store
        self.photoStore = photoStore
        self.library = library
        stage = Self.initialStage(challenge: challenge, permission: camera.permission)
        syncCameraState()
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
            syncCameraState() // lens list and zoom differ per camera
        }
    }

    /// Pulls the service's current framing state into observable properties.
    private func syncCameraState() {
        isFlashOn = camera.isFlashOn
        isUsingFrontCamera = camera.isUsingFrontCamera
        zoomOptions = camera.zoomOptions
        displayZoomFactor = camera.displayZoomFactor
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

    /// Pinch-to-zoom and preset taps share this path; the service clamps and
    /// we mirror whatever it accepted.
    public func setDisplayZoom(_ factor: CGFloat) {
        camera.setDisplayZoom(CameraZoom.clamp(factor, to: zoomOptions))
        displayZoomFactor = camera.displayZoomFactor
    }

    /// Front camera has no lens row — one button toggles the two framings,
    /// the way the built-in Camera app does.
    public func toggleFrontZoom() {
        guard let first = zoomOptions.first, let last = zoomOptions.last, first != last else { return }
        setDisplayZoom(displayZoomFactor >= last ? first : last)
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

    // MARK: Gallery import (PRD open question #6; §18.2 allows a selected photo)

    /// Asks for library access as the camera opens, then fills the gallery
    /// button and grid.
    ///
    /// This deliberately departs from PRD §18.1 (ask at the action that needs
    /// it): the IG-style thumbnail has to read the library before the user
    /// touches anything, and the product owner accepted that trade.
    public func prepareLibraryAccess() {
        thumbnailTask?.cancel()
        thumbnailTask = Task { [library] in
            var access = await library.access()
            if access == .notDetermined {
                access = await library.requestAccess()
            }
            guard !Task.isCancelled else { return }
            libraryAccess = access

            guard access.canBrowse else { return }
            let assets = await library.recentAssets(limit: Self.recentAssetLimit)
            var thumbnail: CGImage?
            if let newest = assets.first {
                thumbnail = await library.thumbnail(for: newest.id, maxPixel: 120)
            }
            guard !Task.isCancelled else { return }
            recentAssets = assets
            galleryThumbnail = thumbnail
        }
    }

    // ponytail: newest 120 photos, no paging — plenty for picking an outfit
    // shot; add paging if anyone scrolls to the bottom and complains.
    private static let recentAssetLimit = 120

    /// Tapping a grid cell imports immediately — no confirm step.
    public func importAsset(id: String) {
        importTask?.cancel()
        importTask = Task { [library] in
            let data = await library.imageData(for: id)
            guard !Task.isCancelled else { return }
            guard let data else {
                Log.report(AppError.photoImportFailed)
                alertError = .photoImportFailed
                return
            }
            isGalleryPresented = false
            await persistPickedPhoto(data)
        }
    }

    /// The picker itself failed to hand over any bytes.
    public func reportImportFailure() {
        alertError = .photoImportFailed
    }

    /// Same safe ordering as a capture: validate, write the file, persist the
    /// id, then move on (FR-016). Undecodable data persists nothing.
    public func usePickedPhoto(_ data: Data) {
        importTask?.cancel()
        importTask = Task {
            await persistPickedPhoto(data)
        }
    }

    /// Shared by the in-app grid and the system-picker fallback.
    private func persistPickedPhoto(_ data: Data) async {
        let bytes = data
        let isDecodable = await Task.detached(priority: .userInitiated) {
            ImageDecoding.downsampledImage(from: bytes, maxPixel: 64) != nil
        }.value
        guard !Task.isCancelled else { return }
        guard isDecodable else {
            Log.report(AppError.photoImportFailed)
            alertError = .photoImportFailed
            return
        }
        // ponytail: HEIC keeps its bytes inside a `.jpg` file — every read
        // goes through CGImageSource, which sniffs content, not names.
        persistPhoto(data)
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
