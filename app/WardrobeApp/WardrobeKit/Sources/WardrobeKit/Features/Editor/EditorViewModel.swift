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
        case drawing(DrawingContent)
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
    public internal(set) var exportState: Loadable<ExportedPhoto> = .idle
    public var isExportPresented = false
    public var isStickerPickerPresented = false
    public var isBackgroundPickerPresented = false
    public var isLayerPanelPresented = false
    public var alertError: AppError?
    public internal(set) var didSaveToPhotos = false
    public internal(set) var isSaving = false

    private var challenge: ActiveChallenge
    private let activeRepository: ActiveChallengeRepository
    private let photoRepository: PhotoRepository
    let librarySaver: PhotoLibrarySaveService
    private let preferencesRepository: AccountPreferencesRepository
    private(set) var loadTask: Task<Void, Never>?
    var exportTask: Task<Void, Never>?
    var saveTask: Task<Void, Never>?

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

    /// The pen survives between sessions; the strokes do not.
    public private(set) var pen = DrawingPen()

    public func beginDrawing() {
        select(nil)
        pen.isErasing = false
        activeTool = .drawing(.empty)
    }

    public func setPen(color: DrawingColor) {
        pen.color = color
        // Picking a colour is asking to draw, not to keep erasing.
        pen.isErasing = false
    }

    public func setPen(width: DrawingWidth) {
        pen.width = width
    }

    public func toggleEraser() {
        pen.isErasing.toggle()
    }

    /// One finished drag: a stroke to add, or an eraser pass to apply.
    public func finishStroke(_ points: [DrawingPoint], canvasSize: CGSize) {
        guard case let .drawing(session) = activeTool else { return }

        let stroke = DrawingStroke(points: points, color: pen.color, width: pen.width)
        guard
            let updated = session.applying(
                stroke,
                pen: pen,
                heightOverWidth: canvasSize.width > 0 ? canvasSize.height / canvasSize.width : 1
            )
        else {
            return
        }

        activeTool = .drawing(updated)
    }

    public func clearDrawing() {
        guard case .drawing = activeTool else { return }
        activeTool = .drawing(.empty)
    }

    /// Commits the session as one layer. Nothing drawn means nothing added —
    /// and the document is never touched until this point, which is what makes
    /// cancelling free (FR-019).
    public func finishDrawing(canvasSize: CGSize) {
        guard case let .drawing(session) = activeTool else { return }
        activeTool = nil

        guard let id = document.appendDrawing(session, canvasSize: canvasSize) else { return }
        selectedLayerID = id
        persistDocument()
    }

    public func beginCrop() {
        activeTool = .crop(
            document.photoCrop ?? CropSpec(rect: CGRect(x: 0, y: 0, width: 1, height: 1))
        )
    }

    public func beginNewText(at position: CGPoint = CGPoint(x: 0.5, y: 0.5)) {
        activeTool = .text(
            TextDraft(
                content: TextContent(content: ""), transform: ElementTransform(position: position)
            ),
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
        case .drawing:
            // Committing a drawing needs the canvas size to trim the layer to
            // its marks, so it has its own entry point.
            return
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

    // MARK: Layer panel (FR-090 reorder, FR-086 lock, §19 discrete adjustment)

    public func moveLayer(id: UUID, _ move: EditorDocument.LayerMove) {
        document.moveLayer(id: id, move)
        persistDocument()
    }

    /// The panel's drag, as an order rather than a move — see
    /// `reorderLayers(topFirstIDs:)` for why that distinction is the fix and
    /// not a preference.
    ///
    /// Selection is deliberately left alone: with an order there is no "the
    /// layer that moved" to select, and reaching for one is what put the
    /// selection on an untouched layer while the delta version was misfiring.
    public func reorderLayers(topFirstIDs ids: [UUID]) {
        let before = document.layers.map(\.id)
        document.reorderLayers(topFirstIDs: ids)
        guard document.layers.map(\.id) != before else { return }

        persistDocument()
    }

    /// Locking selects, because the panel is the only way back to a locked
    /// layer — the canvas ignores its gestures (FR-086).
    public func setLock(_ isLocked: Bool, ofLayer id: UUID) {
        document.setLock(isLocked, ofLayer: id)
        selectedLayerID = id
        persistDocument()
    }

    public func duplicateLayer(id: UUID) {
        guard let copy = document.duplicateLayer(id: id) else { return }
        selectedLayerID = copy
        persistDocument()
    }

    /// §19's discrete adjustment. Routed through `commitTransform` so it
    /// inherits the locked-layer refusal and the scale bound rather than
    /// repeating them.
    func step(_ step: LayerStep, layerID: UUID) {
        guard let layer = document.layer(id: layerID) else { return }
        commitTransform(layerID: layerID, to: LayerStep.apply(step, to: layer.transform))
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
}
