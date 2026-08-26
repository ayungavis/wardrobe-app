@preconcurrency import AVFoundation
import CoreGraphics
import Foundation
import Observation

@MainActor
@Observable
public final class CaptureFlowViewModel {
    public private(set) var stage: CaptureStage
    public private(set) var challenge: ActiveChallenge
    public var alertError: AppError?
    public private(set) var isCapturing = false
    public private(set) var isFlashOn = false
    public private(set) var isUsingFrontCamera = false
    public private(set) var displayZoomFactor: CGFloat = CameraZoom.standard
    public private(set) var zoomOptions: [CGFloat] = [CameraZoom.standard]
    public private(set) var focusPoint: CGPoint?
    public private(set) var galleryThumbnail: CGImage?
    public private(set) var libraryAccess: PhotoLibraryAccess = .notDetermined
    public private(set) var recentAssets: [PhotoAsset] = []
    public private(set) var isTipsPresented = false
    public internal(set) var timer: CaptureTimer = .off
    public internal(set) var countdown: Int?
    public var isGalleryPresented = false

    private let library: PhotoLibraryService

    public internal(set) var isCompleted = false
    var pendingUndoSteps: [EditorDocument] = []
    public internal(set) var isCompleting = false
    public private(set) var didResumeDraft = false

    public let review: GarmentReviewModel

    private let camera: CameraService
    let sleep: @Sendable (Duration) async throws -> Void
    let wardrobeRepository: WardrobeItemRepository
    let thumbnails: GarmentThumbnailRepository
    let syncNow: () async -> Void
    private let preferences: AccountPreferencesRepository
    let activeRepository: ActiveChallengeRepository
    let completedRepository: CompletedChallengeRepository
    let photoRepository: PhotoRepository
    let previews: CompletionPreviewRepository
    let outbox: any OutboxRepository
    let uploads: any MediaUploadRepository
    private(set) var consentTask: Task<Void, Never>?
    private(set) var captureTask: Task<Void, Never>?
    private(set) var sessionTask: Task<Void, Never>?
    private(set) var flipTask: Task<Void, Never>?
    private(set) var importTask: Task<Void, Never>?
    private(set) var thumbnailTask: Task<Void, Never>?
    var countdownTask: Task<Void, Never>?
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
        thumbnails: GarmentThumbnailRepository,
        preferences: AccountPreferencesRepository,
        outbox: any OutboxRepository,
        uploads: any MediaUploadRepository,
        syncNow: @escaping () async -> Void = {},
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.challenge = challenge
        self.camera = camera
        self.sleep = sleep
        self.activeRepository = activeRepository
        self.completedRepository = completedRepository
        self.photoRepository = photoRepository
        self.previews = previews
        self.library = library
        self.wardrobeRepository = wardrobeRepository
        self.thumbnails = thumbnails
        self.syncNow = syncNow
        self.preferences = preferences
        self.outbox = outbox
        self.uploads = uploads
        review = GarmentReviewModel(
            scanner: scanner,
            photoRepository: photoRepository,
            wardrobeRepository: wardrobeRepository,
            thumbnails: thumbnails
        )
        stage = Self.initialStage(
            challenge: challenge,
            permission: camera.permission
        )
        isTipsPresented = stage == .camera && !preferences.load().hasSeenCaptureTips
        didResumeDraft = stage == .editor
        syncCameraState()
    }

    static func initialStage(challenge: ActiveChallenge, permission: CameraPermission) -> CaptureStage {
        if let photoID = challenge.photoID {
            let layerID = challenge.document.photoLayerID(showing: photoID)
            let crop = layerID.flatMap { challenge.document.crop(ofLayer: $0) }
            return crop == nil ? .crop : .editor
        }
        switch permission {
        case .granted: return .camera
        case .notDetermined: return .consent
        case .denied, .restricted: return .denied
        }
    }

    // MARK: Consent / permission (FR-013, FR-014)

    public func thumbnail(forAsset assetID: String) async -> CGImage? {
        await library.thumbnail(for: assetID, maxPixel: 200)
    }

    public func consentContinue() {
        consentTask = Task {
            let result = await camera.requestPermission()
            if result == .granted {
                stage = .camera
                isTipsPresented = !preferences.load().hasSeenCaptureTips
            } else {
                stage = .denied
            }
        }
    }

    public func recheckPermission() {
        switch stage {
        case .consent, .denied, .camera:
            stage = Self.initialStage(
                challenge: challenge,
                permission: camera.permission
            )
        case .crop, .scanReview, .editor:
            break
        }
    }

    public func tipsContinue(dontShowAgain: Bool) {
        if dontShowAgain {
            var stored = preferences.load()
            stored.hasSeenCaptureTips = true
            preferences.save(stored)
        }
        isTipsPresented = false
    }

    // MARK: Camera session (FR-015)

    public func cameraAppeared() {
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

    public func cameraDisappeared() {
        sessionTask?.cancel()
        cancelCountdown()
        camera.stopSession()
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

    func captureNow() {
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
            } catch {
                Log.report(error, logger: Log.ui)
                alertError = .captureFailed
            }
        }
    }

    public func toggleFlash() {
        camera.toggleFlash()
        isFlashOn = camera.isFlashOn
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
        focusPoint = point
    }

    private func persistPhoto(_ data: Data) {
        do {
            let id = try photoRepository.saveOriginal(data)
            challenge.photoID = id
            challenge.document = EditorDocument(photoID: id)
            activeRepository.save(challenge)
            stage = .crop
        } catch {
            Log.report(error)
            alertError = .captureFailed
        }
    }

    public func useCrop(_ crop: CropSpec) {
        guard let photoID = challenge.photoID,
              let layerID = challenge.document.photoLayerID(showing: photoID)
        else {
            return
        }
        challenge.document.setCrop(crop, ofLayer: layerID)
        activeRepository.save(challenge)
        stage = .scanReview
        review.scanIfNeeded(photoID: photoID)
    }

    public func continueToEditor() {
        stage = .editor
    }

    // MARK: Gallery import (PRD open question #6; §18.2 allows a selected photo)

    public func discardPhoto() {
        review.cancel()
        photoRepository.deleteOriginals(of: challenge.document, and: challenge.photoID)
        challenge.photoID = nil
        challenge.document = EditorDocument(layers: [])
        challenge.importedPhotoIDs = []
        activeRepository.save(challenge)
        stage = .camera
    }
}

// MARK: - Photo library import

public extension CaptureFlowViewModel {
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

    func reportImportFailure() {
        alertError = .photoImportFailed
    }

    func usePickedPhoto(_ data: Data) {
        importTask?.cancel()
        importTask = Task {
            await persistPickedPhoto(data)
        }
    }

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
