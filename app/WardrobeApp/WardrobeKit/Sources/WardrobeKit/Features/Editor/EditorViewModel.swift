import CoreGraphics
import Foundation
import Observation

@MainActor
@Observable
public final class EditorViewModel {
    public static let maximumTextLength = 280

    public enum CropTarget: Equatable {
        case layer(UUID)
        case background
    }

    public enum Tool: Equatable {
        case crop(CropTarget)
        case text(TextDraft, isNew: Bool)
        case drawing(DrawingContent)
    }

    /// ponytail: every photo's bytes live here at once. Two or three is fine;
    /// if a document ever holds many, read them back from the repository at
    /// export time instead.
    public internal(set) var originals: Loadable<[String: Data]> = .idle
    public internal(set) var previewImages: [String: CGImage] = [:]
    public internal(set) var croppedPreviews: [String: CGImage] = [:]
    public internal(set) var document: EditorDocument

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

    var history = DocumentHistory()

    public private(set) var pen = DrawingPen()

    public func beginDrawing() {
        select(nil)
        pen.isErasing = false
        activeTool = .drawing(.empty)
    }

    public func setPen(color: DrawingColor) {
        pen.color = color
        pen.isErasing = false
    }

    public func setPen(width: DrawingWidth) {
        pen.width = width
    }

    public func toggleEraser() {
        pen.isErasing.toggle()
    }

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

    public func finishDrawing(canvasSize: CGSize) {
        guard case let .drawing(session) = activeTool else { return }
        activeTool = nil

        guard let id = document.appendDrawing(session, canvasSize: canvasSize) else { return }
        selectedLayerID = id
        persistDocument()
    }

    public func beginCrop(_ target: CropTarget) {
        guard photoID(for: target) != nil else { return }
        activeTool = .crop(target)
    }

    public var croppingPhotoID: String? {
        guard case let .crop(target) = activeTool else { return nil }
        return photoID(for: target)
    }

    public var croppingCrop: CropSpec? {
        guard case let .crop(target) = activeTool else { return nil }
        switch target {
        case let .layer(id): return document.crop(ofLayer: id)
        case .background: return document.background.crop
        }
    }

    public var croppingAspectRatio: CGFloat {
        guard case .crop(.background) = activeTool else { return CropGeometry.photoAspectRatio }
        return StoryCanvas.aspectRatio
    }

    private func photoID(for target: CropTarget) -> String? {
        switch target {
        case let .layer(id):
            guard case let .photo(content) = document.layer(id: id)?.content else { return nil }
            return content.photoID
        case .background:
            return document.background.photoID
        }
    }

    public func commitCrop(_ crop: CropSpec, for target: CropTarget) {
        switch target {
        case let .layer(id):
            document.setCrop(crop, ofLayer: id)
        case .background:
            guard let id = document.background.photoID else { return }
            document.background = .photo(id: id, crop: crop)
        }
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
            if draft.isBlank {
                document.removeLayer(id: draft.id)
            } else {
                document.upsertText(draft)
            }
        case .crop, .drawing:
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

    func persistDocument() {
        guard challenge.document != document else { return }

        history.record(challenge.document)
        write(document)
    }

    func write(_ document: EditorDocument) {
        challenge.document = document
        activeRepository.save(challenge)
        didSaveToPhotos = false
    }

    // MARK: Canvas layers (FR-085 select/transform, FR-087 delete)

    public func select(_ id: UUID?) {
        selectedLayerID = id
    }

    public func commitTransform(layerID: UUID, to transform: ElementTransform) {
        document.updateTransform(ofLayer: layerID, to: transform)
        persistDocument()
    }

    public func removeLayer(id: UUID) {
        guard canRemove(layerID: id) else { return }

        document.removeLayer(id: id)
        if selectedLayerID == id {
            selectedLayerID = nil
        }
        persistDocument()
    }

    public func setBackground(_ background: CanvasBackground) {
        guard document.background != background else { return }
        document.background = background
        persistDocument()
    }

    public func setBackgroundPhoto(_ data: Data) {
        do {
            let photoID = try photoRepository.saveOriginal(data)
            challenge.importedPhotoIDs.append(photoID)

            if case var .loaded(originals) = originals {
                originals[photoID] = data
                self.originals = .loaded(originals)
            }
            previewImages[photoID] = ImageDecoding.downsampledImage(from: data, maxPixel: 1600)

            document.background = .photo(id: photoID, crop: nil)
            updateCroppedPreviews()
            persistDocument()
        } catch {
            Log.report(error)
            alertError = .photoImportFailed
        }
    }

    // MARK: Stickers (PRD FR-019)

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

    private func rememberSticker(_ id: String) {
        var preferences = preferencesRepository.load()
        preferences.remember(stickerID: id)
        preferencesRepository.save(preferences)
    }
}
