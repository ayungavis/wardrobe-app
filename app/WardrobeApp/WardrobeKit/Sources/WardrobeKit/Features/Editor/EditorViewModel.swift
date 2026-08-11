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
    public private(set) var draft: EditDraft
    public private(set) var activeTool: Tool?
    public private(set) var exportState: Loadable<ExportedPhoto> = .idle
    public var isExportPresented = false
    public var isStickerPickerPresented = false
    public var alertError: AppError?
    public private(set) var didSaveToPhotos = false
    public private(set) var isSaving = false

    private var challenge: ActiveChallenge
    private let store: ActiveChallengeStore
    private let photoStore: PhotoStore
    private let librarySaver: PhotoLibrarySaving
    private(set) var loadTask: Task<Void, Never>?
    private(set) var exportTask: Task<Void, Never>?
    private(set) var saveTask: Task<Void, Never>?

    public init(
        challenge: ActiveChallenge,
        store: ActiveChallengeStore,
        photoStore: PhotoStore,
        librarySaver: PhotoLibrarySaving
    ) {
        self.challenge = challenge
        self.store = store
        self.photoStore = photoStore
        self.librarySaver = librarySaver
        draft = challenge.draft
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
                let photoStore = photoStore
                // Full decode + downsample stay off the main actor.
                let (data, preview) = try await Task.detached(priority: .userInitiated) {
                    let data = try photoStore.loadOriginal(id: photoID)
                    let preview = ImageDecoding.downsampledImage(from: data, maxPixel: 1600)
                    return (data, preview)
                }.value
                try Task.checkCancellation()
                previewImage = preview
                originalData = .loaded(data)
            } catch is CancellationError {
                // Ignore cancellation.
            } catch {
                Log.report(error)
                originalData = .failed(AppError(wrapping: error))
            }
        }
    }

    /// Preview with the committed crop applied (cheap — `cropping` shares pixels).
    public var croppedPreviewImage: CGImage? {
        guard let previewImage else { return nil }
        guard let crop = draft.crop else { return previewImage }
        let rect = CGRect(
            x: crop.rect.origin.x * CGFloat(previewImage.width),
            y: crop.rect.origin.y * CGFloat(previewImage.height),
            width: crop.rect.width * CGFloat(previewImage.width),
            height: crop.rect.height * CGFloat(previewImage.height)
        ).integral
        return previewImage.cropping(to: rect) ?? previewImage
    }

    // MARK: Tools (FR-019: cancel restores last committed state)

    public func beginCrop() {
        activeTool = .crop(draft.crop ?? CropSpec(rect: CGRect(x: 0, y: 0, width: 1, height: 1)))
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
            draft.crop = spec
        case let .text(item, _):
            let trimmed = item.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                draft.texts.removeAll { $0.id == item.id }
            } else if let index = draft.texts.firstIndex(where: { $0.id == item.id }) {
                draft.texts[index] = item
            } else {
                draft.texts.append(item)
            }
        case nil:
            return
        }
        activeTool = nil
        persistDraft()
    }

    public func cancelTool() {
        activeTool = nil
    }

    public func removeWorkingText() {
        guard case let .text(item, _) = activeTool else { return }
        draft.texts.removeAll { $0.id == item.id }
        activeTool = nil
        persistDraft()
    }

    private func persistDraft() {
        challenge.draft = draft
        store.save(challenge)
    }

    // MARK: Direct manipulation on committed overlays (story-style drag/pinch)

    public func moveText(id: UUID, to position: CGPoint) {
        guard let index = draft.texts.firstIndex(where: { $0.id == id }) else { return }
        draft.texts[index].position = position.clampedToUnit()
    }

    public func scaleText(id: UUID, to scale: CGFloat) {
        guard let index = draft.texts.firstIndex(where: { $0.id == id }) else { return }
        draft.texts[index].scale = min(3, max(0.5, scale))
    }

    public func removeText(id: UUID) {
        draft.texts.removeAll { $0.id == id }
        persistDraft()
    }

    // MARK: Stickers (PRD FR-019)

    public func addSticker(_ emoji: String) {
        draft.stickers.append(StickerItem(emoji: emoji))
        isStickerPickerPresented = false
        persistDraft()
    }

    public func moveSticker(id: UUID, to position: CGPoint) {
        guard let index = draft.stickers.firstIndex(where: { $0.id == id }) else { return }
        draft.stickers[index].position = position.clampedToUnit()
    }

    public func scaleSticker(id: UUID, to scale: CGFloat) {
        guard let index = draft.stickers.firstIndex(where: { $0.id == id }) else { return }
        draft.stickers[index].scale = min(4, max(0.5, scale))
    }

    public func removeSticker(id: UUID) {
        draft.stickers.removeAll { $0.id == id }
        persistDraft()
    }

    /// Persist once when the gesture ends — not on every frame.
    public func finishDirectManipulation() {
        persistDraft()
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
                let photo = try ExportRenderer.render(original: data, draft: draft)
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
                let photo = try ExportRenderer.render(original: data, draft: draft)
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

private extension CGPoint {
    func clampedToUnit() -> CGPoint {
        CGPoint(x: min(1, max(0, x)), y: min(1, max(0, y)))
    }
}
