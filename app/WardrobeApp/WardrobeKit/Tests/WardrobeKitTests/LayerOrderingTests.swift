import Foundation
import Testing
@testable import WardrobeKit

/// What the layer panel does to a document (FR-090, FR-086, FR-087), tested on
/// the document so the rules hold whichever control invokes them.
struct LayerOrderingTests {
    private func makeDocument() -> EditorDocument {
        EditorDocument(layers: [
            EditorLayer(content: .photo(PhotoContent(photoID: id("photo-1")))),
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

    // MARK: Dragging in the panel

    /// The reason this takes an order and not a move.
    ///
    /// `List` can deliver one drag more than once. A delta applied twice
    /// scrambles the stack — the bug this replaced turned "move row 3 to row 1"
    /// into two hops and landed three layers in the wrong places. An order
    /// applied twice is the same as applied once.
    @Test func applyingTheSameOrderTwiceIsTheSameAsApplyingItOnce() {
        var document = makeDocument()
        let ids = document.layers.map(\.id)
        let requested = [ids[1], ids[2], ids[0]]

        document.reorderLayers(topFirstIDs: requested)
        let once = document.layers.map(\.id)
        document.reorderLayers(topFirstIDs: requested)

        #expect(document.layers.map(\.id) == once)
    }

    @Test func theRequestedOrderIsWhatTheStackEndsUpIn() {
        var document = makeDocument()
        let ids = document.layers.map(\.id)

        // Top of the stack first, so the stack itself reads the other way.
        document.reorderLayers(topFirstIDs: [ids[0], ids[2], ids[1]])

        #expect(document.layers.map(\.id) == [ids[1], ids[2], ids[0]])
    }

    /// Reordering must never be a way to lose or invent a layer, so anything
    /// that is not a permutation of what exists is refused whole.
    @Test func anOrderThatIsNotAPermutationChangesNothing() {
        var document = makeDocument()
        let ids = document.layers.map(\.id)
        let before = document

        document.reorderLayers(topFirstIDs: [ids[0], ids[1]])
        document.reorderLayers(topFirstIDs: ids + [UUID()])
        document.reorderLayers(topFirstIDs: [ids[0], ids[1], UUID()])
        document.reorderLayers(topFirstIDs: [ids[0], ids[0], ids[1]])
        document.reorderLayers(topFirstIDs: [])

        #expect(document == before)
    }

    /// The same invariant the drag used to carry: reordering permutes, it never
    /// touches what a layer is.
    @Test func reorderingKeepsEveryLayerIntact() {
        var document = makeDocument()
        let locked = document.layers[1].id
        document.setLock(true, ofLayer: locked)
        let contents = document.layers.map(\.content)

        // The order it is already in — top of the stack first, so reversed.
        document.reorderLayers(topFirstIDs: document.layers.reversed().map(\.id))

        #expect(document.layers.map(\.content) == contents)
        #expect(document.layer(id: locked)?.isLocked == true)
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
