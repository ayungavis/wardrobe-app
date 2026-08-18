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

    /// A whole drawing session becomes one layer, trimmed to its own marks so
    /// it behaves like every other layer once committed. An empty session
    /// commits nothing.
    @discardableResult
    mutating func appendDrawing(_ content: DrawingContent, canvasSize: CGSize) -> UUID? {
        guard let fitted = DrawingFitting.fit(content, canvasSize: canvasSize) else { return nil }

        let layer = EditorLayer(content: .drawing(fitted.content), transform: fitted.transform)
        layers.append(layer)
        return layer.id
    }

    mutating func appendSticker(_ art: StickerArt) {
        layers.append(EditorLayer(content: .sticker(StickerContent(art: art))))
    }

    // MARK: Layer panel (FR-090)

    /// Where a layer goes in the stack.
    ///
    /// One mutation with four behaviours rather than four mutations: z-order is
    /// a single invariant, and §19 asks the panel for all four, not just the
    /// one-step moves the canvas offers.
    enum LayerMove: Equatable, Sendable {
        case forward, backward, front, back
    }

    /// An unknown id, or a layer already at that end of the stack, changes
    /// nothing — so a panel button with nowhere to go is a no-op rather than a
    /// reorder that quietly moves the wrong layer.
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

    /// Puts the stack in the given order, top of the stack first.
    ///
    /// Takes an order rather than a move, because a move is not idempotent:
    /// `List` can deliver one drag more than once, and a delta applied twice
    /// scrambles the stack while an absolute order applied twice is the same as
    /// applied once.
    ///
    /// Refuses anything that is not a permutation of the layers that exist — an
    /// unknown id or a missing one means the caller is working from a stale
    /// list, and reordering must never be a way to lose a layer.
    mutating func reorderLayers(topFirstIDs ids: [UUID]) {
        let existing = layers.map(\.id)
        guard ids.count == existing.count, Set(ids) == Set(existing) else { return }

        let byID = Dictionary(uniqueKeysWithValues: layers.map { ($0.id, $0) })
        layers = ids.reversed().compactMap { byID[$0] }
    }

    /// The only thing that writes `isLocked`. FR-086: locking changes nothing
    /// about how a layer renders or exports — it is the gate that
    /// `updateTransform` and `removeLayer` already check.
    mutating func setLock(_ isLocked: Bool, ofLayer id: UUID) {
        guard let index = layers.firstIndex(where: { $0.id == id }) else { return }
        layers[index].isLocked = isLocked
    }

    /// The copy lands on top, offset by one step so it is visibly a second
    /// layer, and is always unlocked even when its source was — duplicating a
    /// locked layer to get an editable one is a reason to do this.
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
