import CoreGraphics
import Foundation
import Testing
@testable import WardrobeKit

final class SpyLibrarySaver: PhotoLibrarySaving, @unchecked Sendable {
    var saveError: Error?
    private(set) var savedData: [Data] = []

    func save(_ data: Data) async throws {
        if let saveError {
            throw saveError
        }
        savedData.append(data)
    }
}

@MainActor
struct EditorViewModelTests {
    private func makeSUT(
        store: InMemoryActiveChallengeStore = InMemoryActiveChallengeStore(),
        photoStore: SpyPhotoStore = SpyPhotoStore(),
        librarySaver: SpyLibrarySaver = SpyLibrarySaver(),
        draft: EditDraft = EditDraft()
    ) throws -> EditorViewModel {
        let photoID = try photoStore.saveOriginal(SampleCameraService.makeSampleJPEG(width: 100, height: 200))
        var challenge = ActiveChallenge(card: ChallengeCard(prompt: "x"), acceptedAt: .distantPast)
        challenge.photoID = photoID
        challenge.draft = draft
        store.stored = challenge
        return EditorViewModel(
            challenge: challenge,
            store: store,
            photoStore: photoStore,
            librarySaver: librarySaver
        )
    }

    @Test func loadDecodesOriginalAndPreview() async throws {
        let sut = try makeSUT()

        sut.load()
        await sut.loadTask?.value

        if case .loaded = sut.originalData {} else {
            Issue.record("expected loaded, got \(sut.originalData)")
        }
        #expect(sut.previewImage != nil)
    }

    @Test func commitCropPersistsDraftToStore() throws {
        let store = InMemoryActiveChallengeStore()
        let sut = try makeSUT(store: store)
        let spec = CropSpec(rect: CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.5))

        sut.beginCrop()
        sut.updateWorking(crop: spec)
        sut.commitTool()

        #expect(sut.draft.crop == spec)
        #expect(store.stored?.draft.crop == spec)
        #expect(sut.activeTool == nil)
    }

    @Test func cancelToolDiscardsWorkingChanges() throws {
        let store = InMemoryActiveChallengeStore()
        let committed = EditDraft(crop: CropSpec(rect: CGRect(x: 0, y: 0, width: 1, height: 1)))
        let sut = try makeSUT(store: store, draft: committed)

        sut.beginCrop()
        sut.updateWorking(crop: CropSpec(rect: CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4)))
        sut.cancelTool()

        #expect(sut.draft == committed)
        #expect(store.stored?.draft == committed)
    }

    @Test func commitNewTextAppendsAndEmptyTextIsDropped() throws {
        let store = InMemoryActiveChallengeStore()
        let sut = try makeSUT(store: store)

        sut.beginNewText()
        guard case var .text(working, _) = sut.activeTool else {
            Issue.record("expected text tool")
            return
        }
        working.content = "OOTD"
        sut.updateWorking(text: working)
        sut.commitTool()
        #expect(sut.draft.texts.map(\.content) == ["OOTD"])
        #expect(store.stored?.draft.texts.map(\.content) == ["OOTD"])

        sut.beginNewText()
        sut.commitTool() // empty content — dropped
        #expect(sut.draft.texts.count == 1)
    }

    @Test func editingExistingTextUpdatesInPlace() throws {
        let item = TextItem(content: "old")
        let sut = try makeSUT(draft: EditDraft(texts: [item]))

        sut.beginEditingText(item)
        var updated = item
        updated.content = "new"
        sut.updateWorking(text: updated)
        sut.commitTool()

        #expect(sut.draft.texts.map(\.content) == ["new"])
        #expect(sut.draft.texts.count == 1)
    }

    @Test func removeWorkingTextDeletesAndPersists() throws {
        let store = InMemoryActiveChallengeStore()
        let item = TextItem(content: "bye")
        let sut = try makeSUT(store: store, draft: EditDraft(texts: [item]))

        sut.beginEditingText(item)
        sut.removeWorkingText()

        #expect(sut.draft.texts.isEmpty)
        #expect(store.stored?.draft.texts.isEmpty == true)
        #expect(sut.activeTool == nil)
    }

    @Test func moveAndScaleTextClampAndPersistOnFinish() throws {
        let store = InMemoryActiveChallengeStore()
        let item = TextItem(content: "hi")
        let sut = try makeSUT(store: store, draft: EditDraft(texts: [item]))

        sut.moveText(id: item.id, to: CGPoint(x: 1.7, y: -0.3))
        sut.scaleText(id: item.id, to: 9)
        #expect(sut.draft.texts[0].position == CGPoint(x: 1, y: 0)) // clamped
        #expect(sut.draft.texts[0].scale == 3) // clamped
        #expect(store.stored?.draft.texts.first?.scale == 1) // not persisted yet

        sut.finishDirectManipulation()
        #expect(store.stored?.draft.texts.first?.scale == 3) // persisted at gesture end
    }

    @Test func moveUnknownTextIDIsNoOp() throws {
        let sut = try makeSUT(draft: EditDraft(texts: [TextItem(content: "hi")]))
        let before = sut.draft

        sut.moveText(id: UUID(), to: CGPoint(x: 0.1, y: 0.1))
        sut.scaleText(id: UUID(), to: 2)

        #expect(sut.draft == before)
    }

    @Test func beginNewTextUsesTapPosition() throws {
        let sut = try makeSUT()

        sut.beginNewText(at: CGPoint(x: 0.25, y: 0.75))

        guard case let .text(working, isNew) = sut.activeTool else {
            Issue.record("expected text tool")
            return
        }
        #expect(isNew)
        #expect(working.position == CGPoint(x: 0.25, y: 0.75))
    }

    // MARK: Stickers (FR-019)

    @Test func addStickerAppendsCenteredAndPersists() throws {
        let store = InMemoryActiveChallengeStore()
        let sut = try makeSUT(store: store)

        sut.isStickerPickerPresented = true
        sut.addSticker("🔥")

        #expect(sut.draft.stickers.map(\.emoji) == ["🔥"])
        #expect(sut.draft.stickers[0].position == CGPoint(x: 0.5, y: 0.5))
        #expect(store.stored?.draft.stickers.count == 1)
        #expect(!sut.isStickerPickerPresented)
    }

    @Test func moveAndScaleStickerClampAndPersistOnFinish() throws {
        let store = InMemoryActiveChallengeStore()
        let sticker = StickerItem(emoji: "✨")
        let sut = try makeSUT(store: store, draft: EditDraft(stickers: [sticker]))

        sut.moveSticker(id: sticker.id, to: CGPoint(x: -1, y: 2))
        sut.scaleSticker(id: sticker.id, to: 99)
        #expect(sut.draft.stickers[0].position == CGPoint(x: 0, y: 1))
        #expect(sut.draft.stickers[0].scale == 4)

        sut.finishDirectManipulation()
        #expect(store.stored?.draft.stickers.first?.scale == 4)
    }

    @Test func removeStickerPersists() throws {
        let store = InMemoryActiveChallengeStore()
        let sticker = StickerItem(emoji: "✨")
        let sut = try makeSUT(store: store, draft: EditDraft(stickers: [sticker]))

        sut.removeSticker(id: sticker.id)

        #expect(sut.draft.stickers.isEmpty)
        #expect(store.stored?.draft.stickers.isEmpty == true)
    }

    // MARK: Direct save (save pill)

    @Test func saveDirectlyRendersAndSaves() async throws {
        let librarySaver = SpyLibrarySaver()
        let sut = try makeSUT(librarySaver: librarySaver)
        sut.load()
        await sut.loadTask?.value

        sut.saveDirectly()
        await sut.saveTask?.value

        #expect(librarySaver.savedData.count == 1)
        #expect(sut.didSaveToPhotos)
        #expect(!sut.isSaving)
    }

    @Test func saveDirectlyFailureSetsError() async throws {
        let librarySaver = SpyLibrarySaver()
        librarySaver.saveError = AppError.photoSaveFailed
        let sut = try makeSUT(librarySaver: librarySaver)
        sut.load()
        await sut.loadTask?.value

        sut.saveDirectly()
        await sut.saveTask?.value

        #expect(!sut.didSaveToPhotos)
        #expect(sut.alertError == .photoSaveFailed)
    }

    // MARK: Legacy draft decoding (fields added over time)

    @Test func legacyDraftJSONDecodesWithDefaults() throws {
        let legacy = Data("""
        {"texts":[{"id":"11111111-2222-3333-4444-555555555555","content":"old","position":[0.5,0.5],"scale":1}]}
        """.utf8)

        let draft = try JSONDecoder().decode(EditDraft.self, from: legacy)

        #expect(draft.texts.count == 1)
        #expect(draft.texts[0].colorName == TextColor.white.rawValue)
        #expect(draft.texts[0].hasBackground == false)
        #expect(draft.stickers.isEmpty)
    }

    @Test func originalBytesNeverChangeAfterCommits() throws {
        let photoStore = SpyPhotoStore()
        let sut = try makeSUT(photoStore: photoStore)
        let originalBytes = photoStore.saved.values.first

        sut.beginCrop()
        sut.updateWorking(crop: CropSpec(rect: CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6)))
        sut.commitTool()

        #expect(photoStore.saved.values.first == originalBytes) // §18.5 write-once
    }
}
