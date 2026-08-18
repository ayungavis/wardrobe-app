import CoreGraphics
import Foundation
import Observation

@MainActor
@Observable
public final class EditorViewModel {
    /// A story caption, not an essay. Long enough for anything anyone types on
    /// a photo, short enough that a paste never becomes the whole document.
    public static let maximumTextLength = 280

    public enum Tool: Equatable {
        case crop(CropSpec)
        case text(TextDraft, isNew: Bool)
    }

    public private(set) var originalData: Loadable<Data> = .idle
    public private(set) var previewImage: CGImage?
    /// Derived from `previewImage` + the committed crop. Stored (not computed)
    /// so moving an overlay never re-crops the image on the render path.
    public private(set) var croppedPreviewImage: CGImage?
    /// The layered canvas (FR-084) — what every edit changes, what gets
    /// stored, and what the exporter renders. One shape, so there is nothing
    /// to keep in step.
    public private(set) var document: EditorDocument

    /// Canvas selection. UI state, deliberately not part of the document —
    /// which layer someone is holding means nothing on their other phone.
    public private(set) var selectedLayerID: UUID?
    public private(set) var activeTool: Tool?
    public private(set) var exportState: Loadable<ExportedPhoto> = .idle
    public var isExportPresented = false
    public var isStickerPickerPresented = false
    public var isBackgroundPickerPresented = false
    public var alertError: AppError?
    public private(set) var didSaveToPhotos = false
    public private(set) var isSaving = false

    private var challenge: ActiveChallenge
    private let activeRepository: ActiveChallengeRepository
    private let photoRepository: PhotoRepository
    private let librarySaver: PhotoLibrarySaveService
    private let preferencesRepository: AccountPreferencesRepository
    private(set) var loadTask: Task<Void, Never>?
    private(set) var exportTask: Task<Void, Never>?
    private(set) var saveTask: Task<Void, Never>?

    public init(
        challenge: ActiveChallenge,
        activeRepository: ActiveChallengeRepository,
        photoRepository: PhotoRepository,
        librarySaver: PhotoLibrarySaveService,
        preferencesRepository: AccountPreferencesRepository
    ) {
        self.challenge = challenge
        self.activeRepository = activeRepository
        self.photoRepository = photoRepository
        self.librarySaver = librarySaver
        self.preferencesRepository = preferencesRepository
        document = challenge.document
    }

    public func onAppear() {
        guard case .idle = originalData else { return }
        load()
    }

    public func load() {
        guard let photoID = challenge.photoID else {
            originalData = .failed(.unexpected)
            return
        }

        loadTask?.cancel()
        originalData = .loading

        loadTask = Task {
            do {
                let photoRepository = photoRepository
                // Full decode + downsample stay off the main actor.
                let (data, preview) = try await Task.detached(priority: .userInitiated) {
                    let data = try photoRepository.loadOriginal(id: photoID)
                    let preview = ImageDecoding.downsampledImage(from: data, maxPixel: 1600)
                    return (data, preview)
                }.value
                try Task.checkCancellation()
                previewImage = preview
                updateCroppedPreview()
                originalData = .loaded(data)
            } catch is CancellationError {
                // Ignore cancellation.
            } catch {
                Log.report(error)
                originalData = .failed(AppError(wrapping: error))
            }
        }
    }

    /// Recomputes the cropped preview. Called only when its inputs change —
    /// after the photo loads and after a crop is committed.
    private func updateCroppedPreview() {
        guard let previewImage else {
            croppedPreviewImage = nil
            return
        }
        guard let crop = document.photoCrop else {
            croppedPreviewImage = previewImage
            return
        }
        let rect = CGRect(
            x: crop.rect.origin.x * CGFloat(previewImage.width),
            y: crop.rect.origin.y * CGFloat(previewImage.height),
            width: crop.rect.width * CGFloat(previewImage.width),
            height: crop.rect.height * CGFloat(previewImage.height)
        ).integral
        croppedPreviewImage = previewImage.cropping(to: rect) ?? previewImage
    }

    // MARK: Tools (FR-019: cancel restores last committed state)

    public func beginCrop() {
        activeTool = .crop(document.photoCrop ?? CropSpec(rect: CGRect(x: 0, y: 0, width: 1, height: 1)))
    }

    public func beginNewText(at position: CGPoint = CGPoint(x: 0.5, y: 0.5)) {
        activeTool = .text(
            TextDraft(content: TextContent(content: ""), transform: ElementTransform(position: position)),
            isNew: true
        )
    }

    public func beginEditingText(_ draft: TextDraft) {
        activeTool = .text(draft, isNew: false)
    }

    public func updateWorking(crop: CropSpec) {
        guard case .crop = activeTool else { return }
        activeTool = .crop(crop)
    }

    /// The length cap lives here rather than in the text field: it is a rule
    /// about what gets stored, and here it can be tested without a keyboard.
    public func updateWorking(text: TextDraft) {
        guard case let .text(_, isNew) = activeTool else { return }
        var capped = text
        if capped.content.content.count > Self.maximumTextLength {
            capped.content.content = String(capped.content.content.prefix(Self.maximumTextLength))
        }
        activeTool = .text(capped, isNew: isNew)
    }

    public func commitTool() {
        switch activeTool {
        case let .crop(spec):
            document.photoCrop = spec
            updateCroppedPreview()
        case let .text(draft, _):
            // Blank means nothing was written; what gets stored otherwise is
            // exactly what the user typed.
            if draft.isBlank {
                document.removeLayer(id: draft.id)
            } else {
                document.upsertText(draft)
            }
        case nil:
            return
        }
        activeTool = nil
        persistDocument()
    }

    public func cancelTool() {
        activeTool = nil
    }

    public func removeWorkingText() {
        guard case let .text(draft, _) = activeTool else { return }
        document.removeLayer(id: draft.id)
        activeTool = nil
        persistDocument()
    }

    private func persistDocument() {
        challenge.document = document
        activeRepository.save(challenge)
    }

    // MARK: Canvas layers (FR-085 select/transform, FR-087 delete)

    public func select(_ id: UUID?) {
        selectedLayerID = id
    }

    /// One write per gesture. The canvas renders the live transform itself, so
    /// the document only ever sees the settled one — which is also what makes
    /// "an interrupted transform restores the last committed state" true by
    /// construction rather than by cleanup.
    public func commitTransform(layerID: UUID, to transform: ElementTransform) {
        document.updateTransform(ofLayer: layerID, to: transform)
        persistDocument()
    }

    public func removeLayer(id: UUID) {
        document.removeLayer(id: id)
        if selectedLayerID == id {
            selectedLayerID = nil
        }
        persistDocument()
    }

    /// FR-091. The picker stays open so the choice can be compared against the
    /// canvas behind it, which is the whole reason to have swatches.
    public func setBackground(_ background: CanvasBackground) {
        guard document.background != background else { return }
        document.background = background
        persistDocument()
    }

    // MARK: Stickers (PRD FR-019)

    /// Recently used ids, newest first, with anything the catalogue no longer
    /// ships filtered out (FR-099).
    public var recentStickerIDs: [String] {
        preferencesRepository.load().knownRecentStickerIDs
    }

    public func addSticker(_ entry: StickerCatalogueEntry) {
        document.appendSticker(.catalogue(entry.id))
        selectedLayerID = document.layers.last?.id
        isStickerPickerPresented = false
        persistDocument()
        rememberSticker(entry.id)
    }

    /// Written after the document, never before: a preference is convenience,
    /// and FR-099 is explicit that it must never block a core action.
    private func rememberSticker(_ id: String) {
        var preferences = preferencesRepository.load()
        preferences.remember(stickerID: id)
        preferencesRepository.save(preferences)
    }

    // MARK: Export / save / share (FR-031/032 — independent of completion)

    public func beginExport() {
        guard case let .loaded(data) = originalData else { return }
        exportTask?.cancel()
        exportState = .loading
        didSaveToPhotos = false
        isExportPresented = true

        let document = document
        exportTask = Task {
            do {
                let start = ContinuousClock.now
                let photo = try ExportService.render(original: data, document: document)
                try Task.checkCancellation()
                Log.ui.info("Export finished in \((ContinuousClock.now - start).ms, privacy: .public)ms")
                exportState = .loaded(ExportedPhoto(data: photo))
            } catch is CancellationError {
                // Ignore cancellation.
            } catch {
                Log.report(error)
                exportState = .failed(.exportFailed)
            }
        }
    }

    public func saveToPhotos() {
        guard case let .loaded(photo) = exportState else { return }
        saveTask = Task {
            do {
                try await librarySaver.save(photo.data)
                didSaveToPhotos = true
            } catch {
                Log.report(error)
                alertError = .photoSaveFailed
            }
        }
    }

    /// Save-pill path: render + save to the library in one step, no sheet.
    public func saveDirectly() {
        guard case let .loaded(data) = originalData, !isSaving, !didSaveToPhotos else { return }
        isSaving = true

        let document = document
        saveTask = Task {
            defer { isSaving = false }
            do {
                let photo = try ExportService.render(original: data, document: document)
                try Task.checkCancellation()
                try await librarySaver.save(photo)
                didSaveToPhotos = true
            } catch is CancellationError {
                // Ignore cancellation.
            } catch {
                Log.report(error)
                alertError = .photoSaveFailed
            }
        }
    }
}
