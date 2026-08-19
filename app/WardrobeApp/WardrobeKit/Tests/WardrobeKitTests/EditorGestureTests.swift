import Foundation
import Testing
@testable import WardrobeKit

/// The one rule the move of gesture ownership actually introduces: which layer
/// a press is allowed to latch. Everything else about that move is SwiftUI
/// wiring, which no unit test can reach.
struct EditorGestureTests {
    private func makeLayer(isLocked: Bool = false) -> EditorLayer {
        var layer = EditorLayer(content: .sticker(StickerContent(art: StickerArt(legacyEmoji: "✨"))))
        layer.isLocked = isLocked
        return layer
    }

    @Test func anOrdinaryLayerCanBeHeld() {
        #expect(EditorGesture.canHold(makeLayer(), activeTool: nil))
    }

    /// FR-086: a locked layer keeps its geometry. Refusing the hold is what
    /// makes the pinch fall through to nothing rather than being ignored later.
    @Test func aLockedLayerCannotBeHeld() {
        #expect(!EditorGesture.canHold(makeLayer(isLocked: true), activeTool: nil))
    }

    /// Same bug, other half: the tap that comes with that second finger must
    /// not move the selection either.
    @Test func aTapCannotSelectAnotherLayerWhileOneIsHeld() {
        let held = UUID()

        #expect(!EditorGesture.canSelect(UUID(), whileHolding: held))
        #expect(EditorGesture.canSelect(held, whileHolding: held))
        #expect(EditorGesture.canSelect(UUID(), whileHolding: nil))
    }

    @Test func noLayerCanBeHeldWhileAToolIsOpen() {
        let layer = makeLayer()
        #expect(!EditorGesture.canHold(layer, activeTool: .drawing(.empty)))
        #expect(!EditorGesture.canHold(layer, activeTool: .crop(.layer(UUID()))))
        #expect(!EditorGesture.canHold(layer, activeTool: .text(TextDraft(content: TextContent(content: "hi")), isNew: true)))
    }
}
