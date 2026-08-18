import CoreGraphics
import Foundation
import Testing
@testable import WardrobeKit

final class SpyLibrarySaver: PhotoLibrarySaveService, @unchecked Sendable {
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
        activeRepository: InMemoryActiveChallengeRepository = InMemoryActiveChallengeRepository(),
        photoRepository: SpyPhotoRepository = SpyPhotoRepository(),
        librarySaver: SpyLibrarySaver = SpyLibrarySaver(),
        document: EditorDocument? = nil
    ) throws -> EditorViewModel {
        let photoID = try photoRepository.saveOriginal(SampleCameraService.makeSampleJPEG(width: 100, height: 200))
        var challenge = ActiveChallenge(card: ChallengeCard(prompt: "x"), acceptedAt: .distantPast)
        challenge.photoID = photoID
        challenge.document = document ?? EditorDocument(photoID: photoID)
        activeRepository.stored = challenge
        return EditorViewModel(
            challenge: challenge,
            activeRepository: activeRepository,
            photoRepository: photoRepository,
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
        let activeRepository = InMemoryActiveChallengeRepository()
        let sut = try makeSUT(activeRepository: activeRepository)
        let spec = CropSpec(rect: CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.5))

        sut.beginCrop()
        sut.updateWorking(crop: spec)
        sut.commitTool()

        #expect(sut.document.photoCrop == spec)
        #expect(activeRepository.stored?.document.photoCrop == spec)
        #expect(sut.activeTool == nil)
    }

    @Test func cancelToolDiscardsWorkingChanges() throws {
        let activeRepository = InMemoryActiveChallengeRepository()
        let committed = EditorDocument.fixture(crop: CropSpec(rect: CGRect(x: 0, y: 0, width: 1, height: 1)))
        let sut = try makeSUT(activeRepository: activeRepository, document: committed)

        sut.beginCrop()
        sut.updateWorking(crop: CropSpec(rect: CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4)))
        sut.cancelTool()

        #expect(sut.document == committed)
        #expect(activeRepository.stored?.document == committed)
    }

    @Test func commitNewTextAppendsAndEmptyTextIsDropped() throws {
        let activeRepository = InMemoryActiveChallengeRepository()
        let sut = try makeSUT(activeRepository: activeRepository)

        sut.beginNewText()
        guard case var .text(working, _) = sut.activeTool else {
            Issue.record("expected text tool")
            return
        }
        working.content = "OOTD"
        sut.updateWorking(text: working)
        sut.commitTool()
        #expect(sut.document.textContents == ["OOTD"])
        #expect(activeRepository.stored?.document.textContents == ["OOTD"])

        sut.beginNewText()
        sut.commitTool() // empty content — dropped
        #expect(sut.document.textItems.count == 1)
    }

    @Test func editingExistingTextUpdatesInPlace() throws {
        let item = TextItem(content: "old")
        let sut = try makeSUT(document: .fixture(texts: [item]))

        sut.beginEditingText(item)
        var updated = item
        updated.content = "new"
        sut.updateWorking(text: updated)
        sut.commitTool()

        #expect(sut.document.textContents == ["new"])
        #expect(sut.document.textItems.count == 1)
    }

    @Test func removeWorkingTextDeletesAndPersists() throws {
        let activeRepository = InMemoryActiveChallengeRepository()
        let item = TextItem(content: "bye")
        let sut = try makeSUT(activeRepository: activeRepository, document: .fixture(texts: [item]))

        sut.beginEditingText(item)
        sut.removeWorkingText()

        #expect(sut.document.textItems.isEmpty)
        #expect(activeRepository.stored?.document.textItems.isEmpty == true)
        #expect(sut.activeTool == nil)
    }

    // MARK: Canvas layers (FR-085 select/transform, FR-087 delete)

    /// There is deliberately no mid-gesture entry point any more: the canvas
    /// renders the live transform itself and the view model is told once, at
    /// the end. "Not persisted on every frame" is now a property of the API
    /// rather than something a test has to police.
    @Test func committingATransformStoresItClampedAndPersists() throws {
        let activeRepository = InMemoryActiveChallengeRepository()
        let item = TextItem(content: "hi")
        let sut = try makeSUT(activeRepository: activeRepository, document: .fixture(texts: [item]))

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
        let sut = try makeSUT(document: .fixture(texts: [moved, other], stickers: [sticker]))

        sut.commitTransform(layerID: moved.id, to: ElementTransform(position: CGPoint(x: 0.1, y: 0.1)))

        #expect(sut.document.textItems.first { $0.id == other.id }?.position == CGPoint(x: 0.5, y: 0.5))
        #expect(sut.document.stickerItems[0].position == CGPoint(x: 0.5, y: 0.5))
    }

    @Test func transformingAnUnknownLayerChangesNothing() throws {
        let sut = try makeSUT(document: .fixture(texts: [TextItem(content: "hi")]))
        let before = sut.document

        sut.commitTransform(layerID: UUID(), to: ElementTransform(position: CGPoint(x: 0.1, y: 0.1), scale: 2))

        #expect(sut.document == before)
    }

    @Test func removingALayerPersistsAndClearsTheSelection() throws {
        let activeRepository = InMemoryActiveChallengeRepository()
        let item = TextItem(content: "bye")
        let sut = try makeSUT(activeRepository: activeRepository, document: .fixture(texts: [item]))
        sut.select(item.id)

        sut.removeLayer(id: item.id)

        #expect(sut.document.textItems.isEmpty)
        #expect(activeRepository.stored?.document.textItems.isEmpty == true)
        #expect(sut.selectedLayerID == nil)
    }

    /// Selection is UI state, so it must not reach the stored document.
    @Test func selectingALayerDoesNotTouchTheDocument() throws {
        let activeRepository = InMemoryActiveChallengeRepository()
        let item = TextItem(content: "hi")
        let sut = try makeSUT(activeRepository: activeRepository, document: .fixture(texts: [item]))
        let stored = activeRepository.stored?.document

        sut.select(item.id)

        #expect(sut.selectedLayerID == item.id)
        #expect(activeRepository.stored?.document == stored)
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
        let activeRepository = InMemoryActiveChallengeRepository()
        let sut = try makeSUT(activeRepository: activeRepository)

        sut.isStickerPickerPresented = true
        sut.addSticker("🔥")

        #expect(sut.document.stickerEmojis == ["🔥"])
        #expect(sut.document.stickerItems[0].position == CGPoint(x: 0.5, y: 0.5))
        #expect(activeRepository.stored?.document.stickerItems.count == 1)
        #expect(!sut.isStickerPickerPresented)
        // Selected on arrival, so it can be placed without hunting for it.
        #expect(sut.selectedLayerID == sut.document.layers.last?.id)
    }

    // MARK: Derived preview cache (perf guard)

    @Test func croppedPreviewOnlyRecomputesWhenCropChanges() async throws {
        let text = TextItem(content: "hi")
        let sut = try makeSUT(document: .fixture(texts: [text]))
        sut.load()
        await sut.loadTask?.value

        let afterLoad = try #require(sut.croppedPreviewImage)
        #expect(afterLoad.width == 100) // full preview, no crop yet

        sut.commitTransform(layerID: text.id, to: ElementTransform(position: CGPoint(x: 0.2, y: 0.2)))
        #expect(sut.croppedPreviewImage === afterLoad) // untouched by layer edits

        sut.beginCrop()
        sut.updateWorking(crop: CropSpec(rect: CGRect(x: 0, y: 0, width: 0.5, height: 0.5)))
        sut.commitTool()
        let afterCrop = try #require(sut.croppedPreviewImage)
        #expect(afterCrop.width == 50) // recomputed exactly once, on crop commit
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
        #expect(draft.texts[0].rotationDegrees == 0)
        #expect(draft.texts[0].fontStyle == .classic)
        #expect(draft.texts[0].alignmentStyle == .center)
        #expect(draft.stickers.isEmpty)
    }

    @Test func textFontAndAlignmentCommitAndPersist() throws {
        let activeRepository = InMemoryActiveChallengeRepository()
        let item = TextItem(content: "OOTD")
        let sut = try makeSUT(activeRepository: activeRepository, document: .fixture(texts: [item]))

        sut.beginEditingText(item)
        var updated = item
        updated.fontName = TextFontStyle.serif.rawValue
        updated.alignmentName = TextAlignmentStyle.trailing.rawValue
        sut.updateWorking(text: updated)
        sut.commitTool()

        #expect(sut.document.textItems[0].fontStyle == .serif)
        #expect(sut.document.textItems[0].alignmentStyle == .trailing)
        #expect(activeRepository.stored?.document.textItems[0].fontName == TextFontStyle.serif.rawValue)
        #expect(activeRepository.stored?.document.textItems[0].alignmentName
            == TextAlignmentStyle.trailing.rawValue)
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
        let sut = try makeSUT(photoRepository: photoRepository)
        let originalBytes = photoRepository.saved.values.first

        sut.beginCrop()
        sut.updateWorking(crop: CropSpec(rect: CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6)))
        sut.commitTool()

        #expect(photoRepository.saved.values.first == originalBytes) // §18.5 write-once
    }
}
