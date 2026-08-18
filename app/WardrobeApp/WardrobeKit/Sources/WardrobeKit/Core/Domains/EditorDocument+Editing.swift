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
    mutating func upsertText(_ item: TextItem) {
        let transform = ElementTransform(
            position: item.position,
            scale: item.scale,
            rotationDegrees: item.rotationDegrees
        )
        if let index = layers.firstIndex(where: { $0.id == item.id }) {
            guard !layers[index].isLocked else { return }
            layers[index].content = .text(TextContent(item))
            layers[index].transform = transform
        } else {
            layers.append(EditorLayer(id: item.id, content: .text(TextContent(item)), transform: transform))
        }
    }

    mutating func appendSticker(_ emoji: String) {
        layers.append(EditorLayer(content: .sticker(StickerContent(emoji: emoji))))
    }
}

public extension EditorLayer {
    /// The flat form the text composer still edits. It disappears when the
    /// composer learns to edit a layer directly (S5 of the canvas port).
    var textItem: TextItem? {
        guard case let .text(text) = content else { return nil }
        return TextItem(
            id: id,
            content: text.content,
            position: transform.position,
            scale: transform.scale,
            rotationDegrees: transform.rotationDegrees,
            colorName: text.colorName,
            hasBackground: text.hasBackground,
            fontName: text.fontName,
            alignmentName: text.alignmentName
        )
    }
}

// MARK: - Projection back to the flat draft

public extension EditDraft {
    /// The inverse of `EditorDocument(migrating:photoID:)`.
    ///
    /// The document is what the editor works on; this is what still gets stored
    /// and exported, so it runs on every save. It is lossless while a document
    /// holds only photo, text, and sticker layers — which is all the editor can
    /// currently produce — and ids survive both directions, so the round trip
    /// returns the same layers rather than copies of them.
    ///
    /// Drawing layers, `isLocked`, and the canvas background have no home here.
    /// They arrive with the stages that store the document itself.
    init(projecting document: EditorDocument) {
        var crop: CropSpec?
        var texts: [TextItem] = []
        var stickers: [StickerItem] = []

        for layer in document.layers {
            switch layer.content {
            case let .photo(photo):
                crop = photo.crop
            case .text:
                if let item = layer.textItem {
                    texts.append(item)
                }
            case let .sticker(sticker):
                stickers.append(StickerItem(
                    id: layer.id,
                    emoji: sticker.emoji,
                    position: layer.transform.position,
                    scale: layer.transform.scale,
                    rotationDegrees: layer.transform.rotationDegrees
                ))
            case .drawing:
                continue
            }
        }

        self.init(crop: crop, texts: texts, stickers: stickers)
    }
}
