import CoreGraphics
import Foundation

/// The edits the canvas performs on a document.
///
/// They live on the document rather than on the view model for two reasons:
/// they are value mutations that can be tested without a view or an actor, and
/// the rules they enforce — a locked layer does not move, an edit touches
/// exactly one layer — are product rules (FR-085, FR-086, FR-087) that must
/// hold wherever the edit comes from, canvas or layer panel.
public extension EditorDocument {
    /// The crop on the bottom photo layer. A document has at most one photo
    /// until FR-093 allows more; the setter is a no-op when there is none, so a
    /// crop can never be stored somewhere it would not render.
    var photoCrop: CropSpec? {
        get {
            for layer in layers {
                if case let .photo(photo) = layer.content {
                    return photo.crop
                }
            }
            return nil
        }
        set {
            guard let index = layers.firstIndex(where: {
                if case .photo = $0.content {
                    return true
                }
                return false
            }), case let .photo(photo) = layers[index].content else { return }
            layers[index].content = .photo(PhotoContent(photoID: photo.photoID, crop: newValue))
        }
    }

    func layer(id: UUID) -> EditorLayer? {
        layers.first { $0.id == id }
    }

    /// FR-085 literally: an unknown id changes nothing, and a transform never
    /// reaches past the layer it names. FR-086: a locked layer keeps its
    /// geometry until it is unlocked.
    mutating func updateTransform(ofLayer id: UUID, to transform: ElementTransform) {
        guard let index = layers.firstIndex(where: { $0.id == id }), !layers[index].isLocked else { return }
        layers[index].transform = transform.clamped()
    }

    /// FR-087: only unlocked layers can be deleted from the canvas. Unlocking
    /// first is the deliberate act the requirement asks for.
    mutating func removeLayer(id: UUID) {
        guard let index = layers.firstIndex(where: { $0.id == id }), !layers[index].isLocked else { return }
        layers.remove(at: index)
    }

    /// Writes the composer's result back. An existing id updates in place —
    /// keeping its z-position — and a new one lands on top.
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

    mutating func appendSticker(_ emoji: String) {
        layers.append(EditorLayer(content: .sticker(StickerContent(emoji: emoji))))
    }
}
