import CoreGraphics
import Foundation
import Testing
@testable import WardrobeKit

/// The text tool's contract (FR-019): what the composer may change, what gets
/// stored, and what cancelling leaves behind.
@MainActor
struct EditorTextToolTests {
    @Test func commitNewTextAppendsAndEmptyTextIsDropped() throws {
        let activeRepository = InMemoryActiveChallengeRepository()
        let sut = try makeEditorSUT(activeRepository: activeRepository)

        sut.beginNewText()
        guard case var .text(working, _) = sut.activeTool else {
            Issue.record("expected text tool")
            return
        }
        working.content.content = "OOTD"
        sut.updateWorking(text: working)
        sut.commitTool()
        #expect(sut.document.textContents == ["OOTD"])
        #expect(activeRepository.stored?.document.textContents == ["OOTD"])

        sut.beginNewText()
        sut.commitTool() // empty content — dropped
        #expect(sut.document.textItems.count == 1)
    }

    /// Done is the only way out of the composer now, so on an untouched draft it
    /// has to behave as a cancel — not as an edit that happens to change
    /// nothing. The undo stack is what tells the two apart.
    @Test func doneOnABlankNewDraftRecordsNothing() throws {
        let sut = try makeEditorSUT()
        let before = sut.document

        sut.beginNewText()
        sut.commitTool()

        #expect(sut.document == before)
        #expect(!sut.canUndo)
        #expect(sut.activeTool == nil)
    }

    /// Emptying a text that already exists is a deletion, and a deletion is an
    /// edit — so this one *does* take a step, and undo brings the text back.
    @Test func emptyingAnExistingTextDeletesItAndCanBeUndone() throws {
        let item = TextItem(content: "old")
        let sut = try makeEditorSUT(document: .fixture(texts: [item]))
        let draft = try #require(sut.document.layers.compactMap(\.textDraft).first)

        sut.beginEditingText(draft)
        var emptied = draft
        emptied.content.content = ""
        sut.updateWorking(text: emptied)
        sut.commitTool()

        #expect(sut.document.textItems.isEmpty)

        sut.undo()

        #expect(sut.document.textContents == ["old"])
    }

    @Test func editingExistingTextUpdatesInPlace() throws {
        let item = TextItem(content: "old")
        let sut = try makeEditorSUT(document: .fixture(texts: [item]))
        let draft = try #require(sut.document.layers.compactMap(\.textDraft).first)

        sut.beginEditingText(draft)
        var updated = draft
        updated.content.content = "new"
        sut.updateWorking(text: updated)
        sut.commitTool()

        #expect(sut.document.textContents == ["new"])
        #expect(sut.document.textItems.count == 1)
    }

    @Test func removeWorkingTextDeletesAndPersists() throws {
        let activeRepository = InMemoryActiveChallengeRepository()
        let item = TextItem(content: "bye")
        let sut = try makeEditorSUT(activeRepository: activeRepository, document: .fixture(texts: [item]))

        try sut.beginEditingText(#require(sut.document.layers.compactMap(\.textDraft).first))
        sut.removeWorkingText()

        #expect(sut.document.textItems.isEmpty)
        #expect(activeRepository.stored?.document.textItems.isEmpty == true)
        #expect(sut.activeTool == nil)
    }

    /// A caption, not an essay — and the cap lives in the view model so a
    /// paste is trimmed wherever it arrives from, not only from the keyboard.
    @Test func textLongerThanTheCapIsTrimmed() throws {
        let sut = try makeEditorSUT()
        sut.beginNewText()
        guard case var .text(working, _) = sut.activeTool else {
            Issue.record("expected text tool")
            return
        }

        working.content.content = String(repeating: "a", count: EditorViewModel.maximumTextLength + 40)
        sut.updateWorking(text: working)

        guard case let .text(capped, _) = sut.activeTool else {
            Issue.record("expected text tool")
            return
        }
        #expect(capped.content.content.count == EditorViewModel.maximumTextLength)
    }

    @Test func textWithinTheCapIsLeftAlone() throws {
        let sut = try makeEditorSUT()
        sut.beginNewText()
        guard case var .text(working, _) = sut.activeTool else {
            Issue.record("expected text tool")
            return
        }

        working.content.content = "OOTD"
        sut.updateWorking(text: working)

        guard case let .text(kept, _) = sut.activeTool else {
            Issue.record("expected text tool")
            return
        }
        #expect(kept.content.content == "OOTD")
    }

    @Test func beginNewTextUsesTapPosition() throws {
        let sut = try makeEditorSUT()

        sut.beginNewText(at: CGPoint(x: 0.25, y: 0.75))

        guard case let .text(working, isNew) = sut.activeTool else {
            Issue.record("expected text tool")
            return
        }
        #expect(isNew)
        #expect(working.transform.position == CGPoint(x: 0.25, y: 0.75))
    }

    @Test func textFontAndAlignmentCommitAndPersist() throws {
        let activeRepository = InMemoryActiveChallengeRepository()
        let item = TextItem(content: "OOTD")
        let sut = try makeEditorSUT(activeRepository: activeRepository, document: .fixture(texts: [item]))

        let draft = try #require(sut.document.layers.compactMap(\.textDraft).first)
        sut.beginEditingText(draft)
        var updated = draft
        updated.content.fontName = TextFontStyle.serif.rawValue
        updated.content.alignmentName = TextAlignmentStyle.trailing.rawValue
        sut.updateWorking(text: updated)
        sut.commitTool()

        #expect(sut.document.textItems[0].fontStyle == .serif)
        #expect(sut.document.textItems[0].alignmentStyle == .trailing)
        #expect(activeRepository.stored?.document.textItems[0].fontName == TextFontStyle.serif.rawValue)
        #expect(activeRepository.stored?.document.textItems[0].alignmentName
            == TextAlignmentStyle.trailing.rawValue)
    }
}
