@preconcurrency import AVFoundation
import Foundation
import Observation

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
    public let library: PhotoLibraryService

    /// Set once the checkmark commits — the flow's cover closes on it.
    public internal(set) var isCompleted = false
    /// Read by the editor so the ✓ can show the wait for the garment scan
    /// rather than looking inert.
    public internal(set) var isCompleting = false
    /// True when this session opened onto work that was already there, rather
    /// than work it created. Read by the editor to state that a device-only
    /// draft was restored (§17).
    public private(set) var didResumeDraft = false

    /// The AI item review shown in the editor drawer (FR-027).
    public let review: GarmentReviewModel

    private let camera: CameraService
    let activeRepository: ActiveChallengeRepository
    let completedRepository: CompletedChallengeRepository
    let photoRepository: PhotoRepository
    let previews: CompletionPreviewRepository
    private(set) var consentTask: Task<Void, Never>?
    private(set) var captureTask: Task<Void, Never>?
    private(set) var sessionTask: Task<Void, Never>?
    private(set) var flipTask: Task<Void, Never>?
    private(set) var importTask: Task<Void, Never>?
    private(set) var thumbnailTask: Task<Void, Never>?
    var completionTask: Task<Void, Never>?

    public init(
        challenge: ActiveChallenge,
        camera: CameraService,
        activeRepository: ActiveChallengeRepository,
        completedRepository: CompletedChallengeRepository,
        photoRepository: PhotoRepository,
        previews: CompletionPreviewRepository,
        library: PhotoLibraryService,
        scanner: GarmentScanService,
        wardrobeRepository: WardrobeItemRepository,
        thumbnails: GarmentThumbnailRepository
    ) {
        self.challenge = challenge
        self.camera = camera
        self.activeRepository = activeRepository
        self.completedRepository = completedRepository
        self.photoRepository = photoRepository
        self.previews = previews
        self.library = library
        review = GarmentReviewModel(
            scanner: scanner,
            photoRepository: photoRepository,
            wardrobeRepository: wardrobeRepository,
            thumbnails: thumbnails
        )
        stage = Self.initialStage(challenge: challenge, permission: camera.permission)
        // Landing straight in the editor can only mean the challenge came off
        // disk with the crop already committed — which is exactly the "restored
        // draft" §17 wants stated. No extra flag is persisted to say what the
        // stage already says.
        didResumeDraft = stage == .editor
        syncCameraState()
    }

    static func initialStage(challenge: ActiveChallenge, permission: CameraPermission) -> CaptureStage {
        // Resume where the photo actually is (FR-017). A capture that never got
        // framed reopens the crop step rather than skipping past it — the crop
        // in the draft is what says the step is done, so no extra flag is
        // persisted to say the same thing twice.
        if let photoID = challenge.photoID {
            // The *challenge* photo's crop, not any photo's: a second photo
            // added in the editor must not send the flow back to the crop step
            // (FR-093).
            let layerID = challenge.document.photoLayerID(showing: photoID)
            let crop = layerID.flatMap { challenge.document.crop(ofLayer: $0) }
            return crop == nil ? .crop : .editor
        }
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
        case .crop, .editor:
            // A photo already exists; camera permission cannot un-take it.
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

    /// Ordering matters: file write first, then persist photoID, then the crop
    /// step. A failed write leaves nothing persisted (FR-016).
    private func persistPhoto(_ data: Data) {
        do {
            let id = try photoRepository.saveOriginal(data)
            challenge.photoID = id
            // The photo layer is born with the photo — the crop step and the
            // editor both write into it rather than creating it later.
            challenge.document = EditorDocument(photoID: id)
            activeRepository.save(challenge)
            stage = .crop
        } catch {
            Log.report(error)
            alertError = .captureFailed
        }
    }

    /// **Use Crop** (FR-083): the framing is stored as an instruction, not as a
    /// second image file. The editor's preview and the exporter both already
    /// read `document.photoCrop`, so the original stays the only photo on disk
    /// and is never overwritten (FR-092).
    public func useCrop(_ crop: CropSpec) {
        guard let photoID = challenge.photoID,
              let layerID = challenge.document.photoLayerID(showing: photoID)
        else {
            return
        }
        challenge.document.setCrop(crop, ofLayer: layerID)
        activeRepository.save(challenge)
        stage = .editor
        // Started here rather than left to the editor's own `.task`, so the
        // scan runs alongside the editor loading its photo instead of after it.
        // Idempotent: the model refuses a photo it has already scanned.
        review.scanIfNeeded(photoID: photoID)
    }

    // MARK: Gallery import (PRD open question #6; §18.2 allows a selected photo)

    /// Editor X: throw the photo and its edits away, back to the camera.
    public func discardPhoto() {
        // Every photo the canvas holds, not just the capture (FR-093).
        photoRepository.deleteOriginals(of: challenge.document, and: challenge.photoID)
        challenge.photoID = nil
        challenge.document = EditorDocument(layers: [])
        challenge.importedPhotoIDs = []
        activeRepository.save(challenge)
        stage = .camera
    }
}

// MARK: - Photo library import

/// Grouped in an extension: bringing a photo in from the library is a
/// self-contained errand next to the camera state machine above.
public extension CaptureFlowViewModel {
    /// Asks for library access as the camera opens, then fills the gallery
    /// button and grid.
    ///
    /// This deliberately departs from PRD §18.1 (ask at the action that needs
    /// it): the IG-style thumbnail has to read the library before the user
    /// touches anything, and the product owner accepted that trade.
    func prepareLibraryAccess() {
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
    func importAsset(id: String) {
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
    func reportImportFailure() {
        alertError = .photoImportFailed
    }

    /// Same safe ordering as a capture: validate, write the file, persist the
    /// id, then move on (FR-016). Undecodable data persists nothing.
    func usePickedPhoto(_ data: Data) {
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
}
