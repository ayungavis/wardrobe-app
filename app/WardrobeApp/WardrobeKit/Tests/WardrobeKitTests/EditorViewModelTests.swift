import CoreGraphics
import Foundation
import Testing
@testable import WardrobeKit

@MainActor
struct EditorViewModelTests {
    @Test func loadDecodesOriginalAndPreview() async throws {
        let sut = try makeEditorSUT()

        sut.load()
        await sut.loadTask?.value

        if case .loaded = sut.originals {} else {
            Issue.record("expected loaded, got \(sut.originals)")
        }
        #expect(!sut.previewImages.isEmpty)
    }

    @Test func commitCropPersistsDraftToStore() throws {
        let activeRepository = InMemoryActiveChallengeRepository()
        let sut = try makeEditorSUT(activeRepository: activeRepository)
        let spec = CropSpec(rect: CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.5))

        try sut.commitCrop(spec, ofLayer: #require(sut.document.firstPhotoLayerID))

        #expect(sut.document.firstPhotoCrop == spec)
        #expect(activeRepository.stored?.document.firstPhotoCrop == spec)
        #expect(sut.activeTool == nil)
    }

    /// FR-019: crop is reached by double-tapping the photo, so with no photo
    /// layer there is nothing to double-tap and nothing to open.
    @Test func cropDoesNotOpenWithoutAPhotoLayer() throws {
        let sut = try makeEditorSUT(document: EditorDocument(layers: []))

        sut.beginCrop(layerID: UUID())

        #expect(sut.activeTool == nil)
    }

    /// Nothing to discard any more — the crop screen owns its own framing and
    /// only reports a finished one — so what this pins is that opening and
    /// leaving the tool is not itself an edit.
    @Test func cancellingCropLeavesTheDocumentAlone() throws {
        let activeRepository = InMemoryActiveChallengeRepository()
        let sut = try makeEditorSUT(
            activeRepository: activeRepository,
            document: .fixture(crop: CropSpec(rect: CGRect(x: 0, y: 0, width: 1, height: 1)))
        )
        // Read back rather than reused: the SUT points the fixture's photo layer
        // at the id the repository actually minted.
        let committed = sut.document

        try sut.beginCrop(layerID: #require(sut.document.firstPhotoLayerID))
        sut.cancelTool()

        #expect(sut.document == committed)
        #expect(activeRepository.stored?.document == committed)
    }

    // MARK: Canvas layers (FR-085 select/transform, FR-087 delete)

    /// There is deliberately no mid-gesture entry point any more: the canvas
    /// renders the live transform itself and the view model is told once, at
    /// the end. "Not persisted on every frame" is now a property of the API
    /// rather than something a test has to police.
    @Test func committingATransformStoresItClampedAndPersists() throws {
        let activeRepository = InMemoryActiveChallengeRepository()
        let item = TextItem(content: "hi")
        let sut = try makeEditorSUT(activeRepository: activeRepository, document: .fixture(texts: [item]))

        sut.commitTransform(layerID: item.id, to: ElementTransform(
            position: CGPoint(x: 0.2, y: 0.8), scale: 9, rotationDegrees: 42
        ))

        #expect(sut.document.textItems[0].position == CGPoint(x: 0.2, y: 0.8))
        #expect(sut.document.textItems[0].scale == ElementTransform.scaleRange.upperBound)
        #expect(sut.document.textItems[0].rotationDegrees == 42)
        #expect(activeRepository.stored?.document.textItems.first?.rotationDegrees == 42)
    }

    /// FR-085 word for word: a transform never alters another layer.
    @Test func transformingOneLayerLeavesEveryOtherUntouched() throws {
        let moved = TextItem(content: "moved")
        let other = TextItem(content: "other")
        let sticker = StickerItem(emoji: "✨")
        let sut = try makeEditorSUT(document: .fixture(texts: [moved, other], stickers: [sticker]))

        sut.commitTransform(layerID: moved.id, to: ElementTransform(position: CGPoint(x: 0.1, y: 0.1)))

        #expect(sut.document.textItems.first { $0.id == other.id }?.position == CGPoint(x: 0.5, y: 0.5))
        #expect(sut.document.stickerItems[0].position == CGPoint(x: 0.5, y: 0.5))
    }

    @Test func transformingAnUnknownLayerChangesNothing() throws {
        let sut = try makeEditorSUT(document: .fixture(texts: [TextItem(content: "hi")]))
        let before = sut.document

        sut.commitTransform(layerID: UUID(), to: ElementTransform(position: CGPoint(x: 0.1, y: 0.1), scale: 2))

        #expect(sut.document == before)
    }

    @Test func removingALayerPersistsAndClearsTheSelection() throws {
        let activeRepository = InMemoryActiveChallengeRepository()
        let item = TextItem(content: "bye")
        let sut = try makeEditorSUT(activeRepository: activeRepository, document: .fixture(texts: [item]))
        sut.select(item.id)

        sut.removeLayer(id: item.id)

        #expect(sut.document.textItems.isEmpty)
        #expect(activeRepository.stored?.document.textItems.isEmpty == true)
        #expect(sut.selectedLayerID == nil)
    }

    // MARK: Layer panel (FR-090, FR-086)

    /// Every panel mutation has to reach the stored draft — a reorder that only
    /// lives in memory would come back undone after a relaunch.
    @Test func everyPanelMutationPersists() throws {
        let activeRepository = InMemoryActiveChallengeRepository()
        let first = TextItem(content: "one")
        let second = TextItem(content: "two")
        let sut = try makeEditorSUT(
            activeRepository: activeRepository, document: .fixture(texts: [first, second])
        )

        sut.moveLayer(id: first.id, .front)
        #expect(activeRepository.stored?.document.layers.last?.id == first.id)

        sut.setLock(true, ofLayer: second.id)
        #expect(activeRepository.stored?.document.layer(id: second.id)?.isLocked == true)

        sut.duplicateLayer(id: second.id)
        #expect(activeRepository.stored?.document.layers.count == sut.document.layers.count)

        sut.step(.bigger, layerID: first.id)
        #expect(activeRepository.stored?.document.layer(id: first.id)?.transform.scale == 1 + LayerStep.scaleStep)
    }

    /// Locking selects, because the panel is the only way back to a layer the
    /// canvas has stopped responding to (FR-086).
    @Test func lockingSelectsAndDuplicatingSelectsTheCopy() throws {
        let item = TextItem(content: "hi")
        let sut = try makeEditorSUT(document: .fixture(texts: [item]))

        sut.setLock(true, ofLayer: item.id)
        #expect(sut.selectedLayerID == item.id)

        sut.duplicateLayer(id: item.id)
        #expect(sut.selectedLayerID == sut.document.layers.last?.id)
        #expect(sut.selectedLayerID != item.id)
    }

    /// A locked layer refuses the discrete step for the same reason it refuses
    /// the gesture — one gate, checked in one place.
    @Test func aDiscreteStepRespectsTheLock() throws {
        let item = TextItem(content: "hi")
        let sut = try makeEditorSUT(document: .fixture(texts: [item]))
        sut.setLock(true, ofLayer: item.id)

        sut.step(.rotateRight, layerID: item.id)

        #expect(sut.document.layer(id: item.id)?.transform.rotationDegrees == 0)
    }

    /// Selection is UI state, so it must not reach the stored document.
    @Test func selectingALayerDoesNotTouchTheDocument() throws {
        let activeRepository = InMemoryActiveChallengeRepository()
        let item = TextItem(content: "hi")
        let sut = try makeEditorSUT(activeRepository: activeRepository, document: .fixture(texts: [item]))
        let stored = activeRepository.stored?.document

        sut.select(item.id)

        #expect(sut.selectedLayerID == item.id)
        #expect(activeRepository.stored?.document == stored)
    }

    // MARK: Stickers (FR-019)

    @Test func addStickerAppendsCenteredAndPersists() throws {
        let activeRepository = InMemoryActiveChallengeRepository()
        let sut = try makeEditorSUT(activeRepository: activeRepository)
        let entry = try #require(StickerCatalogue.entry(id: "emoji.fire"))

        sut.isStickerPickerPresented = true
        sut.addSticker(entry)

        #expect(sut.document.stickerArts == [.catalogue("emoji.fire")])
        #expect(sut.document.layers.last?.transform.position == CGPoint(x: 0.5, y: 0.5))
        #expect(activeRepository.stored?.document.stickerArts.count == 1)
        #expect(!sut.isStickerPickerPresented)
        // Selected on arrival, so it can be placed without hunting for it.
        #expect(sut.selectedLayerID == sut.document.layers.last?.id)
    }

    /// FR-099: the preference is written, and written *after* the document —
    /// convenience must never be able to block the edit.
    @Test func pickingAStickerRemembersItAsRecent() throws {
        let preferences = InMemoryAccountPreferencesRepository()
        let sut = try makeEditorSUT(preferencesRepository: preferences)

        try sut.addSticker(#require(StickerCatalogue.entry(id: "sticker.heart")))
        try sut.addSticker(#require(StickerCatalogue.entry(id: "emoji.fire")))
        try sut.addSticker(#require(StickerCatalogue.entry(id: "sticker.heart")))

        // Newest first, and picking the same one twice does not duplicate it.
        #expect(preferences.stored.recentStickerIDs == ["sticker.heart", "emoji.fire"])
        #expect(sut.recentStickerIDs == ["sticker.heart", "emoji.fire"])
    }

    // MARK: Derived preview cache (perf guard)

    @Test func croppedPreviewOnlyRecomputesWhenCropChanges() async throws {
        let text = TextItem(content: "hi")
        let sut = try makeEditorSUT(document: .fixture(texts: [text]))
        sut.load()
        await sut.loadTask?.value

        let photoID = try #require(sut.document.photoIDs.first)
        let afterLoad = try #require(sut.preview(forPhoto: photoID))
        #expect(afterLoad.width == 100) // full preview, no crop yet

        sut.commitTransform(layerID: text.id, to: ElementTransform(position: CGPoint(x: 0.2, y: 0.2)))
        #expect(sut.preview(forPhoto: photoID) === afterLoad) // untouched by layer edits

        try sut.beginCrop(layerID: #require(sut.document.firstPhotoLayerID))
        try sut.commitCrop(
            CropSpec(rect: CGRect(x: 0, y: 0, width: 0.5, height: 0.5)),
            ofLayer: #require(sut.document.firstPhotoLayerID)
        )
        let afterCrop = try #require(sut.preview(forPhoto: photoID))
        #expect(afterCrop.width == 50) // recomputed exactly once, on crop commit
    }

    // MARK: Direct save (save pill)

    @Test func saveDirectlyRendersAndSaves() async throws {
        let librarySaver = SpyLibrarySaver()
        let sut = try makeEditorSUT(librarySaver: librarySaver)
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
        let sut = try makeEditorSUT(librarySaver: librarySaver)
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
        #expect(draft.texts[0].rotationDegrees == 0)
        #expect(draft.texts[0].fontStyle == .classic)
        #expect(draft.texts[0].alignmentStyle == .center)
        #expect(draft.stickers.isEmpty)
    }

    @Test func draftWithPreRotationStickerDecodesWithZeroRotation() throws {
        let legacy = Data("""
        {"stickers":[{"id":"22222222-3333-4444-5555-666666666666","emoji":"🔥","position":[0.5,0.5],"scale":1}]}
        """.utf8)

        let draft = try JSONDecoder().decode(EditDraft.self, from: legacy)

        #expect(draft.stickers.count == 1)
        #expect(draft.stickers[0].rotationDegrees == 0)
    }

    @Test func originalBytesNeverChangeAfterCommits() throws {
        let photoRepository = SpyPhotoRepository()
        let sut = try makeEditorSUT(photoRepository: photoRepository)
        let originalBytes = photoRepository.saved.values.first

        try sut.beginCrop(layerID: #require(sut.document.firstPhotoLayerID))
        try sut.commitCrop(
            CropSpec(rect: CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6)),
            ofLayer: #require(sut.document.firstPhotoLayerID)
        )

        #expect(photoRepository.saved.values.first == originalBytes) // §18.5 write-once
    }
}
