import CoreGraphics
import Foundation
import Testing
@testable import WardrobeKit

/// Undo and redo at the view-model level (FR-088) — its own suite because
/// `EditorViewModelTests` outgrew SwiftLint's body limit, the same way the
/// text and drawing suites were split off.
@MainActor
struct EditorHistoryTests {
    @Test func undoRestoresThePreviousDocumentAndWritesIt() throws {
        let activeRepository = InMemoryActiveChallengeRepository()
        let item = TextItem(content: "hi")
        let sut = try makeEditorSUT(activeRepository: activeRepository, document: .fixture(texts: [item]))
        #expect(!sut.canUndo)

        sut.commitTransform(layerID: item.id, to: ElementTransform(scale: 2))
        #expect(sut.canUndo)
        sut.undo()

        #expect(sut.document.layer(id: item.id)?.transform.scale == 1)
        #expect(activeRepository.stored?.document.layer(id: item.id)?.transform.scale == 1)
        #expect(!sut.canUndo)
        #expect(sut.canRedo)
    }

    @Test func redoWalksTheEditForwardAgain() throws {
        let item = TextItem(content: "hi")
        let sut = try makeEditorSUT(document: .fixture(texts: [item]))
        sut.commitTransform(layerID: item.id, to: ElementTransform(scale: 2))
        sut.undo()

        sut.redo()

        #expect(sut.document.layer(id: item.id)?.transform.scale == 2)
        #expect(!sut.canRedo)
    }

    /// A new edit makes an undone future unreachable.
    @Test func editingAfterAnUndoClosesRedo() throws {
        let item = TextItem(content: "hi")
        let sut = try makeEditorSUT(document: .fixture(texts: [item]))
        sut.commitTransform(layerID: item.id, to: ElementTransform(scale: 2))
        sut.undo()

        sut.setBackground(.mint)

        #expect(!sut.canRedo)
    }

    /// An edit the document refused is not an edit: it must not eat a step that
    /// then does nothing when pressed, and it must not pay for a write either.
    @Test func aRefusedEditRecordsNoStepAndWritesNothing() throws {
        let activeRepository = InMemoryActiveChallengeRepository()
        let item = TextItem(content: "hi")
        let sut = try makeEditorSUT(activeRepository: activeRepository, document: .fixture(texts: [item]))
        sut.setLock(true, ofLayer: item.id)
        let writes = activeRepository.saveCount

        sut.commitTransform(layerID: item.id, to: ElementTransform(scale: 2))
        sut.step(.rotateRight, layerID: item.id)
        sut.removeLayer(id: item.id)

        #expect(activeRepository.saveCount == writes)

        // The lock was the only real edit, so one step returns to before it and
        // leaves nothing behind — three refused edits recorded nothing.
        sut.undo()
        #expect(sut.document.layer(id: item.id)?.isLocked == false)
        #expect(!sut.canUndo)
    }

    /// The cropped preview is stored rather than computed, so stepping across a
    /// crop has to re-derive it — otherwise the canvas keeps the wrong pixels.
    @Test func undoAcrossACropRebuildsThePreview() async throws {
        let sut = try makeEditorSUT()
        sut.load()
        await sut.loadTask?.value
        sut.beginCrop()
        sut.commitCrop(CropSpec(rect: CGRect(x: 0, y: 0, width: 0.5, height: 0.5)))
        #expect(sut.croppedPreviewImage?.width == 50)

        sut.undo()

        #expect(sut.document.photoCrop == nil)
        #expect(sut.croppedPreviewImage?.width == 100)
    }

    /// Selection is view-model state, deliberately outside the document, so
    /// undo does not walk it backwards.
    @Test func undoDoesNotBringBackAnOldSelection() throws {
        let first = TextItem(content: "one")
        let second = TextItem(content: "two")
        let sut = try makeEditorSUT(document: .fixture(texts: [first, second]))
        sut.select(first.id)
        sut.commitTransform(layerID: first.id, to: ElementTransform(scale: 2))
        sut.select(second.id)

        sut.undo()

        #expect(sut.selectedLayerID == second.id)
    }
}
