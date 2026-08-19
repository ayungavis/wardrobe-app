import Foundation
import Testing
@testable import WardrobeKit

/// Export, share, and save at the view-model level (FR-031/032). Saving and
/// sharing are independent of each other and of completion, and most of what is
/// pinned here is that independence holding in both directions.
@MainActor
struct EditorExportTests {
    @Test func sharingRendersAndOpensTheSheet() async throws {
        let sut = try makeEditorSUT()
        sut.load()
        await sut.loadTask?.value

        sut.beginExport()
        #expect(sut.isExporting)
        await sut.exportTask?.value

        #expect(sut.isExportPresented)
        #expect(!sut.isExporting)
        guard case let .loaded(photo) = sut.exportState else {
            Issue.record("expected a rendered photo, got \(sut.exportState)")
            return
        }
        #expect(!photo.data.isEmpty)
    }

    /// Saving and sharing are independent (FR-031), and that has to hold both
    /// ways round: opening the share sheet used to reset the pill, so a photo
    /// already in the library started claiming it was not.
    @Test func sharingDoesNotUndoASaveThatAlreadyHappened() async throws {
        let sut = try makeEditorSUT()
        sut.load()
        await sut.loadTask?.value
        sut.saveDirectly()
        await sut.saveTask?.value
        #expect(sut.didSaveToPhotos)

        sut.beginExport()
        await sut.exportTask?.value

        #expect(sut.didSaveToPhotos)
    }

    /// "Saved" is a claim about the library matching the canvas, so an edit
    /// ends it — and that is also the only way back to saving again, since the
    /// pill is otherwise spent for the session.
    @Test func editingAfterASaveLetsTheUserSaveAgain() async throws {
        let item = TextItem(content: "hi")
        let sut = try makeEditorSUT(document: .fixture(texts: [item]))
        sut.load()
        await sut.loadTask?.value
        sut.saveDirectly()
        await sut.saveTask?.value
        #expect(sut.didSaveToPhotos)

        sut.commitTransform(layerID: item.id, to: ElementTransform(scale: 2))
        #expect(!sut.didSaveToPhotos)

        sut.saveDirectly()
        await sut.saveTask?.value
        #expect(sut.didSaveToPhotos)
    }

    /// An undo changes the canvas as surely as an edit does.
    @Test func undoingAfterASaveAlsoEndsTheClaim() async throws {
        let item = TextItem(content: "hi")
        let sut = try makeEditorSUT(document: .fixture(texts: [item]))
        sut.load()
        await sut.loadTask?.value
        sut.commitTransform(layerID: item.id, to: ElementTransform(scale: 2))
        sut.saveDirectly()
        await sut.saveTask?.value

        sut.undo()

        #expect(!sut.didSaveToPhotos)
    }

    /// PRD §17: duplicate export actions are prevented. The pill disables on
    /// `isExporting`, and a second call cancels the first rather than leaving
    /// two renders racing to set the state.
    @Test func asecondShareReplacesTheFirstRatherThanRacingIt() async throws {
        let sut = try makeEditorSUT()
        sut.load()
        await sut.loadTask?.value

        sut.beginExport()
        let first = sut.exportTask
        sut.beginExport()
        await first?.value
        await sut.exportTask?.value

        #expect(first?.isCancelled == true)
        if case .failed = sut.exportState {
            Issue.record("a replaced export must not leave a failure behind")
        }
    }

    /// A refused permission and a full disk asked the user for the same thing
    /// before, which was no help to either.
    @Test func aDeniedLibraryTellsTheUserItIsAPermission() async throws {
        let saver = SpyLibrarySaver()
        saver.saveError = AppError.photoAccessDenied
        let sut = try makeEditorSUT(librarySaver: saver)
        sut.load()
        await sut.loadTask?.value

        sut.saveDirectly()
        await sut.saveTask?.value

        #expect(sut.alertError == .photoAccessDenied)
        #expect(!sut.didSaveToPhotos)
    }
}
