import CoreGraphics
import Foundation
import Testing
@testable import WardrobeKit

/// More than one photo on a canvas (FR-093). The extra ones are editing
/// material: they never become the challenge's photo and never reach the scan.
@MainActor
struct EditorPhotoTests {
    private func makePhoto() throws -> Data {
        try SampleCameraService.makeSampleJPEG(width: 80, height: 120)
    }

    @Test func addingAPhotoLandsAsANewLayerAndLeavesTheChallengeAlone() async throws {
        let activeRepository = InMemoryActiveChallengeRepository()
        let sut = try makeEditorSUT(activeRepository: activeRepository)
        sut.load()
        await sut.loadTask?.value
        let challengePhoto = try #require(sut.document.photoIDs.first)

        try sut.addPhoto(makePhoto())

        #expect(sut.document.photoIDs.count == 2)
        #expect(sut.document.photoIDs.first == challengePhoto, "the challenge photo stays at the bottom")
        #expect(activeRepository.stored?.photoID == challengePhoto, "and stays the challenge's own")
        #expect(sut.selectedLayerID == sut.document.layers.last?.id)
    }

    /// Each photo carries its own framing — cropping the one you added must not
    /// reframe the capture underneath it.
    @Test func croppingOnePhotoLeavesTheOtherAlone() async throws {
        let sut = try makeEditorSUT()
        sut.load()
        await sut.loadTask?.value
        try sut.addPhoto(makePhoto())
        let challengeLayer = try #require(sut.document.layers.first?.id)
        let addedLayer = try #require(sut.document.layers.last?.id)

        sut.commitCrop(CropSpec(rect: CGRect(x: 0, y: 0, width: 0.5, height: 0.5)), ofLayer: addedLayer)

        #expect(sut.document.crop(ofLayer: addedLayer) != nil)
        #expect(sut.document.crop(ofLayer: challengeLayer) == nil)
    }

    /// The reason a photo's file is never deleted when its layer is: undo hands
    /// the layer back, and a layer pointing at a file that is gone renders
    /// nothing with no way to explain itself.
    @Test func undoingAPhotoDeletionStillHasItsPixels() async throws {
        let photoRepository = SpyPhotoRepository()
        let sut = try makeEditorSUT(photoRepository: photoRepository)
        sut.load()
        await sut.loadTask?.value
        try sut.addPhoto(makePhoto())
        let added = try #require(sut.document.photoIDs.last)
        let addedLayer = try #require(sut.document.layers.last?.id)

        sut.removeLayer(id: addedLayer)
        sut.undo()

        #expect(sut.document.photoIDs.contains(added))
        #expect(sut.preview(forPhoto: added) != nil)
        #expect((try? photoRepository.loadOriginal(id: added)) != nil, "the file outlived the layer")
    }

    /// Deleting the challenge's own photo would leave a challenge that
    /// completes legitimately and shares a picture with no photo in it —
    /// `CompletedChallenge` names that photo, and the export renders the
    /// document.
    @Test func theChallengePhotoCannotBeDeletedButOtherPhotosCan() async throws {
        let sut = try makeEditorSUT()
        sut.load()
        await sut.loadTask?.value
        try sut.addPhoto(makePhoto())
        let challengeLayer = try #require(sut.challengePhotoLayerID)
        let addedLayer = try #require(sut.document.layers.last?.id)

        sut.removeLayer(id: challengeLayer)
        #expect(sut.document.layers.contains { $0.id == challengeLayer })
        #expect(!sut.canRemove(layerID: challengeLayer))

        sut.removeLayer(id: addedLayer)
        #expect(!sut.document.layers.contains { $0.id == addedLayer })
    }

    /// A refused delete is not an edit: it must not eat an undo step that then
    /// does nothing when pressed.
    @Test func aRefusedDeleteLeavesNoUndoStep() async throws {
        let sut = try makeEditorSUT()
        sut.load()
        await sut.loadTask?.value
        let challengeLayer = try #require(sut.challengePhotoLayerID)

        sut.removeLayer(id: challengeLayer)

        #expect(!sut.canUndo)
    }

    /// The rule belongs to the challenge, not to the document — a document
    /// reopened from History protects a different photo. This is what stops it
    /// being moved into `EditorDocument` later by mistake.
    @Test func theDocumentItselfHasNoOpinionAboutTheChallengePhoto() {
        var document = EditorDocument(photoID: "photo-1")
        let layerID = document.layers[0].id

        document.removeLayer(id: layerID)

        #expect(document.layers.isEmpty)
    }

    /// Abandoning takes every photo with it, not just the capture.
    @Test func abandoningRemovesEveryPhotoTheCanvasHeld() async throws {
        let photoRepository = SpyPhotoRepository()
        let activeRepository = InMemoryActiveChallengeRepository()
        let sut = try makeEditorSUT(activeRepository: activeRepository, photoRepository: photoRepository)
        sut.load()
        await sut.loadTask?.value
        try sut.addPhoto(makePhoto())
        let stored = try #require(activeRepository.stored)

        photoRepository.deleteOriginals(of: stored.document, and: stored.photoID)

        #expect(photoRepository.saved.isEmpty)
    }
}
