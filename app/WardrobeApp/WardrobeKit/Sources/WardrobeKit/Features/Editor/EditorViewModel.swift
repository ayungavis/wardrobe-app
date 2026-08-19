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
        case crop(UUID)
        case text(TextDraft, isNew: Bool)
        case drawing(DrawingContent)
    }

    /// Whether the document's photos are on hand. One `Loadable` for all of
    /// them: a canvas with a photo it cannot decode is not half-loaded, it is
    /// broken, and FR-093 wants that said at the layer rather than as a state
    /// of the whole editor.
    /// Every photo's bytes, keyed by id. The exporter re-crops the original
    /// rather than the preview, so the bytes have to stay reachable.
    ///
    /// One `Loadable` for all of them: a canvas with a photo it cannot decode
    /// is not half-loaded, it is broken.
    ///
    /// ponytail: every photo's bytes live here at once. Two or three is fine;
    /// if a document ever holds many, read them back from the repository at
    /// export time instead.
    public internal(set) var originals: Loadable<[String: Data]> = .idle
    public internal(set) var previewImages: [String: CGImage] = [:]
    /// Derived from `previewImages` + each layer's committed crop. Stored (not
    /// computed) so moving an overlay never re-crops on the render path.
    public internal(set) var croppedPreviews: [String: CGImage] = [:]
    /// The layered canvas (FR-084) — what every edit changes, what gets
    /// stored, and what the exporter renders. One shape, so there is nothing
    /// to keep in step.
    ///
    /// `internal(set)` rather than `private(set)` only because this type spans
    /// three files; nothing outside `EditorViewModel*.swift` writes it.
    public internal(set) var document: EditorDocument

    /// Canvas selection. UI state, deliberately not part of the document —
    /// which layer someone is holding means nothing on their other phone.
    public internal(set) var selectedLayerID: UUID?
    public private(set) var activeTool: Tool?
    public internal(set) var exportState: Loadable<ExportedPhoto> = .idle
    public var isExportPresented = false
    public var isStickerPickerPresented = false
    public var isBackgroundPickerPresented = false
    public var isLayerPanelPresented = false
    public var alertError: AppError?
    public internal(set) var didSaveToPhotos = false
    public internal(set) var isSaving = false

    /// Internal rather than private because this type spans five files;
    /// nothing outside `EditorViewModel*.swift` touches it.
    var challenge: ActiveChallenge
    let activeRepository: ActiveChallengeRepository
    let photoRepository: PhotoRepository
    let librarySaver: PhotoLibrarySaveService
    private let preferencesRepository: AccountPreferencesRepository
    var loadTask: Task<Void, Never>?
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
        guard case .idle = originals else { return }
        load()
    }

    // MARK: Tools (FR-019: cancel restores last committed state)

    /// The pen survives between sessions; the strokes do not.
    /// Session-scoped, in memory, never encoded into the challenge — the
    /// stack is the one part of editing that must not outlive the session
    /// (PRD §18.1).
    var history = DocumentHistory()

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

    /// FR-019: crop is not a tool in the rail — it is reached by double-tapping
    /// a photo. FR-093 lets a document hold more than one, so *which* photo is
    /// part of the question.
    public func beginCrop(layerID: UUID) {
        guard case .photo = document.layer(id: layerID)?.content else { return }
        activeTool = .crop(layerID)
    }

    /// The photo a crop in progress belongs to.
    public var croppingPhotoID: String? {
        guard case let .crop(layerID) = activeTool,
              case let .photo(content) = document.layer(id: layerID)?.content
        else {
            return nil
        }
        return content.photoID
    }

    /// One finished framing, straight from the crop screen — there is no
    /// in-flight spec for the editor to hold any more.
    public func commitCrop(_ crop: CropSpec, ofLayer layerID: UUID) {
        document.setCrop(crop, ofLayer: layerID)
        updateCroppedPreviews()
        activeTool = nil
        persistDocument()
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
        case let .text(draft, _):
            // Blank means nothing was written; what gets stored otherwise is
            // exactly what the user typed.
            if draft.isBlank {
                document.removeLayer(id: draft.id)
            } else {
                document.upsertText(draft)
            }
        case .crop, .drawing:
            // Both need something this call does not have — a finished framing,
            // or the canvas size to trim a drawing to its marks — so each has
            // its own entry point.
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

    /// The one choke point every edit already goes through, which is what lets
    /// undo cover all of them without any of them knowing it exists:
    /// `challenge.document` still holds the document as it was before the edit.
    ///
    /// The guard matters twice over. A mutation the document refused — a
    /// transform on a locked layer, a reorder that resolved to the same order —
    /// must not eat an undo step that then does nothing when pressed, and it
    /// must not pay for a JSON encode either.
    func persistDocument() {
        guard challenge.document != document else { return }

        history.record(challenge.document)
        write(document)
    }

    /// Called by `persistDocument` for an edit and by `restore` for an undo —
    /// every path that actually changes the document, and nothing else.
    func write(_ document: EditorDocument) {
        challenge.document = document
        activeRepository.save(challenge)
        // "Saved" claims the library holds what the canvas shows. Changing the
        // canvas ends that claim, which is also what lets someone save again
        // after an edit instead of the pill being spent for the session.
        didSaveToPhotos = false
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
}
