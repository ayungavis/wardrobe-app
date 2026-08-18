import CoreGraphics
import Foundation
import Observation

@MainActor
@Observable
public final class EditorViewModel {
    public enum Tool: Equatable {
        case crop(CropSpec)
        case text(TextItem, isNew: Bool)
    }

    public private(set) var originalData: Loadable<Data> = .idle
    public private(set) var previewImage: CGImage?
    /// Derived from `previewImage` + the committed crop. Stored (not computed)
    /// so moving an overlay never re-crops the image on the render path.
    public private(set) var croppedPreviewImage: CGImage?
    /// The layered canvas (FR-084) — what every edit actually changes.
    public private(set) var document: EditorDocument
    /// What still gets stored and exported. Computed, so it can never drift
    /// from the document the way a second stored copy would.
    ///
    /// ponytail: the document rides inside `EditDraft` for now, which cannot
    /// carry lock flags, the canvas background, or drawings. The stage that
    /// stores documents in their own right replaces this; until then the
    /// projection is lossless because those three do not exist yet.
    public var draft: EditDraft {
        EditDraft(projecting: document)
    }

    /// Canvas selection. UI state, deliberately not part of the document —
    /// which layer someone is holding means nothing on their other phone.
    public private(set) var selectedLayerID: UUID?
    public private(set) var activeTool: Tool?
    public private(set) var exportState: Loadable<ExportedPhoto> = .idle
    public var isExportPresented = false
    public var isStickerPickerPresented = false
    public var alertError: AppError?
    public private(set) var didSaveToPhotos = false
    public private(set) var isSaving = false

    private var challenge: ActiveChallenge
    private let activeRepository: ActiveChallengeRepository
    private let photoRepository: PhotoRepository
    private let librarySaver: PhotoLibrarySaveService
    private(set) var loadTask: Task<Void, Never>?
    private(set) var exportTask: Task<Void, Never>?
    private(set) var saveTask: Task<Void, Never>?

    public init(
        challenge: ActiveChallenge,
        activeRepository: ActiveChallengeRepository,
        photoRepository: PhotoRepository,
        librarySaver: PhotoLibrarySaveService
    ) {
        self.challenge = challenge
        self.activeRepository = activeRepository
        self.photoRepository = photoRepository
        self.librarySaver = librarySaver
        document = EditorDocument(migrating: challenge.draft, photoID: challenge.photoID)
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
        activeTool = .text(TextItem(content: "", position: position), isNew: true)
    }

    public func beginEditingText(_ item: TextItem) {
        activeTool = .text(item, isNew: false)
    }

    public func updateWorking(crop: CropSpec) {
        guard case .crop = activeTool else { return }
        activeTool = .crop(crop)
    }

    public func updateWorking(text: TextItem) {
        guard case let .text(_, isNew) = activeTool else { return }
        activeTool = .text(text, isNew: isNew)
    }

    public func commitTool() {
        switch activeTool {
        case let .crop(spec):
            document.photoCrop = spec
            updateCroppedPreview()
        case let .text(item, _):
            // Trimmed only to decide whether anything was written; what gets
            // stored is what the user typed.
            if item.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                document.removeLayer(id: item.id)
            } else {
                document.upsertText(item)
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
        guard case let .text(item, _) = activeTool else { return }
        document.removeLayer(id: item.id)
        activeTool = nil
        persistDocument()
    }

    private func persistDocument() {
        challenge.draft = draft
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

    // MARK: Stickers (PRD FR-019)

    public func addSticker(_ emoji: String) {
        document.appendSticker(emoji)
        selectedLayerID = document.layers.last?.id
        isStickerPickerPresented = false
        persistDocument()
    }

    // MARK: Export / save / share (FR-031/032 — independent of completion)

    public func beginExport() {
        guard case let .loaded(data) = originalData else { return }
        exportTask?.cancel()
        exportState = .loading
        didSaveToPhotos = false
        isExportPresented = true

        let draft = draft
        exportTask = Task {
            do {
                let start = ContinuousClock.now
                let photo = try ExportService.render(original: data, draft: draft)
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

        let draft = draft
        saveTask = Task {
            defer { isSaving = false }
            do {
                let photo = try ExportService.render(original: data, draft: draft)
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
