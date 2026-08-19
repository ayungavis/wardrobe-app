import CoreGraphics
import Foundation

public extension EditorDocument {
    func crop(ofLayer id: UUID) -> CropSpec? {
        guard case let .photo(photo) = layer(id: id)?.content else { return nil }
        return photo.crop
    }

    mutating func setCrop(_ crop: CropSpec?, ofLayer id: UUID) {
        guard let index = layers.firstIndex(where: { $0.id == id }),
              case let .photo(photo) = layers[index].content
        else {
            return
        }
        layers[index].content = .photo(PhotoContent(photoID: photo.photoID, crop: crop))
    }

    func photoLayerID(showing photoID: String) -> UUID? {
        layers.first {
            if case let .photo(photo) = $0.content {
                return photo.photoID == photoID
            }
            return false
        }?.id
    }

    var photoCrops: [String: CropSpec?] {
        layers.reduce(into: [:]) { result, layer in
            if case let .photo(photo) = layer.content {
                result[photo.photoID] = photo.crop
            }
        }
    }

    var photoIDs: [String] {
        layers.compactMap {
            if case let .photo(photo) = $0.content {
                return photo.photoID
            }
            return nil
        }
    }

    func layer(id: UUID) -> EditorLayer? {
        layers.first { $0.id == id }
    }

    mutating func updateTransform(ofLayer id: UUID, to transform: ElementTransform) {
        guard let index = layers.firstIndex(where: { $0.id == id }), !layers[index].isLocked else { return }
        layers[index].transform = transform.clamped()
    }

    mutating func removeLayer(id: UUID) {
        guard let index = layers.firstIndex(where: { $0.id == id }), !layers[index].isLocked else { return }
        layers.remove(at: index)
    }

    mutating func upsertText(_ draft: TextDraft) {
        if let index = layers.firstIndex(where: { $0.id == draft.id }) {
            guard !layers[index].isLocked else { return }
            layers[index].content = .text(draft.content)
            layers[index].transform = draft.transform.clamped()
        } else {
            layers.append(EditorLayer(
                id: draft.id, content: .text(draft.content), transform: draft.transform.clamped()
            ))
        }
    }

    @discardableResult
    mutating func appendDrawing(_ content: DrawingContent, canvasSize: CGSize) -> UUID? {
        guard let fitted = DrawingFitting.fit(content, canvasSize: canvasSize) else { return nil }

        let layer = EditorLayer(content: .drawing(fitted.content), transform: fitted.transform)
        layers.append(layer)
        return layer.id
    }

    mutating func appendPhoto(_ photoID: String) {
        layers.append(EditorLayer(content: .photo(PhotoContent(photoID: photoID))))
    }

    mutating func appendSticker(_ art: StickerArt) {
        layers.append(EditorLayer(content: .sticker(StickerContent(art: art))))
    }

    // MARK: Layer panel (FR-090)

    enum LayerMove: Equatable, Sendable {
        case forward, backward, front, back
    }

    mutating func moveLayer(id: UUID, _ move: LayerMove) {
        guard let index = layers.firstIndex(where: { $0.id == id }) else { return }

        let destination = switch move {
        case .forward: layers.index(after: index)
        case .backward: layers.index(before: index)
        case .front: layers.index(before: layers.endIndex)
        case .back: layers.startIndex
        }
        guard layers.indices.contains(destination), destination != index else { return }

        layers.insert(layers.remove(at: index), at: destination)
    }

    mutating func reorderLayers(topFirstIDs ids: [UUID]) {
        let existing = layers.map(\.id)
        guard ids.count == existing.count, Set(ids) == Set(existing) else { return }

        let byID = Dictionary(uniqueKeysWithValues: layers.map { ($0.id, $0) })
        layers = ids.reversed().compactMap { byID[$0] }
    }

    mutating func setLock(_ isLocked: Bool, ofLayer id: UUID) {
        guard let index = layers.firstIndex(where: { $0.id == id }) else { return }
        layers[index].isLocked = isLocked
    }

    @discardableResult
    mutating func duplicateLayer(id: UUID) -> UUID? {
        guard let source = layer(id: id) else { return nil }

        let copy = EditorLayer(
            content: source.content,
            transform: LayerStep.apply(.down, to: LayerStep.apply(.right, to: source.transform))
        )
        layers.append(copy)
        return copy.id
    }
}
