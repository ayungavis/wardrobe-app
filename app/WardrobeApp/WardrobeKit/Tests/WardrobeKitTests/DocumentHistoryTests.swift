import Testing
@testable import WardrobeKit

/// The undo stack's own rules, tested on the value type so they hold however
/// the editor calls into it.
struct DocumentHistoryTests {
    private func makeDocument(_ text: String) -> EditorDocument {
        EditorDocument(layers: [EditorLayer(content: .text(TextContent(content: text)))])
    }

    @Test func undoHandsBackWhatWasRecorded() {
        var history = DocumentHistory()
        let first = makeDocument("first")

        history.record(first)

        #expect(history.canUndo)
        #expect(history.undo(current: makeDocument("second")) == first)
    }

    @Test func redoHandsBackWhatUndoSteppedAwayFrom() {
        var history = DocumentHistory()
        let first = makeDocument("first")
        let second = makeDocument("second")
        history.record(first)

        _ = history.undo(current: second)

        #expect(history.canRedo)
        #expect(history.redo(current: first) == second)
    }

    /// A new edit makes an undone future unreachable — keeping it would let
    /// redo jump to a document that never followed from this one.
    @Test func aNewEditClosesOffTheUndoneFuture() {
        var history = DocumentHistory()
        history.record(makeDocument("first"))
        _ = history.undo(current: makeDocument("second"))
        #expect(history.canRedo)

        history.record(makeDocument("third"))

        #expect(!history.canRedo)
    }

    /// Walking forwards must leave the rest of the future reachable, so redo
    /// pushes back onto undo without clearing itself.
    @Test func redoingTwiceWalksForwardsTwice() {
        var history = DocumentHistory()
        let first = makeDocument("first")
        let second = makeDocument("second")
        let third = makeDocument("third")
        history.record(first)
        history.record(second)

        _ = history.undo(current: third)
        _ = history.undo(current: second)

        #expect(history.redo(current: first) == second)
        #expect(history.redo(current: second) == third)
        #expect(!history.canRedo)
    }

    @Test func theCeilingHoldsAndDropsTheOldestStep() {
        var history = DocumentHistory()
        // Built once and kept: every document mints its own id, so a second
        // call could never compare equal to the first.
        let steps = (0 ... DocumentHistory.maximumSteps).map { makeDocument("step \($0)") }
        for step in steps {
            history.record(step)
        }

        #expect(history.undoStack.count == DocumentHistory.maximumSteps)
        #expect(history.undoStack.first == steps[1])
    }

    @Test func steppingWithNothingToStepToChangesNothing() {
        var history = DocumentHistory()
        let before = history

        #expect(history.undo(current: makeDocument("only")) == nil)
        #expect(history.redo(current: makeDocument("only")) == nil)
        #expect(history == before)
    }
}
