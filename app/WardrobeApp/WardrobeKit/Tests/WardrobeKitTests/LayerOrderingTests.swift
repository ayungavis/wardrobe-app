import Foundation
import Testing
@testable import WardrobeKit

/// What the layer panel does to a document (FR-090, FR-086, FR-087), tested on
/// the document so the rules hold whichever control invokes them.
struct LayerOrderingTests {
    private func makeDocument() -> EditorDocument {
        EditorDocument(layers: [
            EditorLayer(content: .photo(PhotoContent(photoID: "photo-1"))),
            EditorLayer(content: .sticker(StickerContent(emoji: "✨"))),
            EditorLayer(content: .text(TextContent(content: "OOTD"))),
        ])
    }

    // MARK: Reordering (FR-090)

    @Test func forwardMovesOnePlaceUpTheStack() {
        var document = makeDocument()
        let ids = document.layers.map(\.id)

        document.moveLayer(id: ids[0], .forward)

        #expect(document.layers.map(\.id) == [ids[1], ids[0], ids[2]])
    }

    @Test func backwardMovesOnePlaceDownTheStack() {
        var document = makeDocument()
        let ids = document.layers.map(\.id)

        document.moveLayer(id: ids[2], .backward)

        #expect(document.layers.map(\.id) == [ids[0], ids[2], ids[1]])
    }

    /// Front and back go all the way, not one step — the difference is the
    /// whole reason §19 asks for both pairs.
    @Test func frontAndBackGoAllTheWay() {
        var document = makeDocument()
        let ids = document.layers.map(\.id)

        document.moveLayer(id: ids[0], .front)
        #expect(document.layers.map(\.id) == [ids[1], ids[2], ids[0]])

        document.moveLayer(id: ids[2], .back)
        #expect(document.layers.map(\.id) == [ids[2], ids[1], ids[0]])
    }

    /// A button with nowhere to go does nothing, rather than wrapping around or
    /// moving a neighbour instead.
    @Test(arguments: [EditorDocument.LayerMove.forward, .front])
    func aLayerAlreadyOnTopStaysThere(_ move: EditorDocument.LayerMove) {
        var document = makeDocument()
        let before = document

        document.moveLayer(id: document.layers[2].id, move)

        #expect(document == before)
    }

    @Test(arguments: [EditorDocument.LayerMove.backward, .back])
    func aLayerAlreadyAtTheBottomStaysThere(_ move: EditorDocument.LayerMove) {
        var document = makeDocument()
        let before = document

        document.moveLayer(id: document.layers[0].id, move)

        #expect(document == before)
    }

    @Test func reorderingAnUnknownLayerChangesNothing() {
        var document = makeDocument()
        let before = document

        document.moveLayer(id: UUID(), .front)

        #expect(document == before)
    }

    /// Reordering is the one mutation allowed to touch a locked layer: FR-086
    /// locks geometry, not the stack.
    @Test func aLockedLayerCanStillBeReordered() {
        var document = makeDocument()
        document.setLock(true, ofLayer: document.layers[0].id)
        let id = document.layers[0].id

        document.moveLayer(id: id, .front)

        #expect(document.layers.last?.id == id)
    }

    // MARK: Lock (FR-086, FR-087)

    @Test func lockingThenUnlockingRestoresEveryEdit() {
        var document = makeDocument()
        let id = document.layers[1].id

        document.setLock(true, ofLayer: id)
        document.updateTransform(ofLayer: id, to: ElementTransform(scale: 2))
        #expect(document.layer(id: id)?.transform == .identity)

        document.setLock(false, ofLayer: id)
        document.updateTransform(ofLayer: id, to: ElementTransform(scale: 2))
        #expect(document.layer(id: id)?.transform.scale == 2)
    }

    /// The other half of `aLockedLayerCannotBeDeletedFromTheCanvas`: unlocking
    /// is the explicit act FR-087 asks for, and it has to actually work.
    @Test func unlockingIsWhatMakesADeleteGoThrough() {
        var document = makeDocument()
        let id = document.layers[1].id
        document.setLock(true, ofLayer: id)

        document.removeLayer(id: id)
        #expect(document.layers.count == 3)

        document.setLock(false, ofLayer: id)
        document.removeLayer(id: id)
        #expect(document.layers.count == 2)
    }

    @Test func lockingAnUnknownLayerChangesNothing() {
        var document = makeDocument()
        let before = document

        document.setLock(true, ofLayer: UUID())

        #expect(document == before)
    }

    // MARK: Duplicate

    @Test func aDuplicateLandsOnTopOffsetFromItsSource() {
        var document = makeDocument()
        let source = document.layers[1]

        let copy = document.duplicateLayer(id: source.id)

        #expect(document.layers.count == 4)
        #expect(document.layers.last?.id == copy)
        #expect(document.layers.last?.content == source.content)
        #expect(document.layers.last?.transform != source.transform)
    }

    /// Duplicating a locked layer to get an editable one is a reason to do
    /// this, so the copy is never locked.
    @Test func aDuplicateOfALockedLayerIsUnlocked() {
        var document = makeDocument()
        let id = document.layers[1].id
        document.setLock(true, ofLayer: id)

        document.duplicateLayer(id: id)

        #expect(document.layers.last?.isLocked == false)
    }

    @Test func duplicatingAnUnknownLayerChangesNothing() {
        var document = makeDocument()
        let before = document

        #expect(document.duplicateLayer(id: UUID()) == nil)
        #expect(document == before)
    }
}
