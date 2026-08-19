import Foundation
import Testing
@testable import WardrobeKit

/// The ✓ — the only action that completes a challenge (FR-012/029/030).
@MainActor
struct CaptureFlowCompletionTests {
    @Test func completeChallengeRecordsCompletionAndClearsActiveChallenge() async {
        let activeRepository = InMemoryActiveChallengeRepository()
        let completedRepository = InMemoryCompletedChallengeRepository()
        let sut = makeEditorStageCaptureFlowSUT(
            activeRepository: activeRepository, completedRepository: completedRepository
        )

        sut.completeChallenge()
        await sut.completionTask?.value

        #expect(completedRepository.stored.count == 1)
        #expect(completedRepository.stored[0].card.prompt == "x")
        #expect(activeRepository.stored == nil)
        #expect(sut.isCompleted)
    }

    /// History shows the composition, not the capture, so ✓ renders it once and
    /// stores it — otherwise every card in the grid would re-render on scroll.
    @Test func completionStoresARenderedPreview() async throws {
        let completedRepository = InMemoryCompletedChallengeRepository()
        let previews = InMemoryCompletionPreviewRepository()
        let sut = makeEditorStageCaptureFlowSUT(
            completedRepository: completedRepository, previews: previews
        )

        sut.completeChallenge()
        await sut.completionTask?.value

        let completion = try #require(completedRepository.stored.first)
        let file = try #require(completion.previewFile)
        #expect(try previews.data(forFile: file).isEmpty == false)
    }

    /// FR-028: a failed render must never cost the user their completion, for
    /// the same reason the wardrobe bookkeeping cannot hold it hostage.
    @Test func completionSurvivesAPreviewThatCannotBeStored() async {
        let completedRepository = InMemoryCompletedChallengeRepository()
        let previews = InMemoryCompletionPreviewRepository()
        previews.saveError = AppError.unexpected
        let sut = makeEditorStageCaptureFlowSUT(
            completedRepository: completedRepository, previews: previews
        )

        sut.completeChallenge()
        await sut.completionTask?.value

        #expect(completedRepository.stored.count == 1)
        #expect(completedRepository.stored.first?.previewFile == nil)
        #expect(sut.isCompleted)
    }

    /// The editor holds its own copy of the challenge and saves edits to the
    /// repository, so the capture flow's copy has been stale since the editor
    /// opened. Trusting the local one dropped every text and sticker at ✓ — the
    /// completed record kept only the crop, which is written on this side.
    @Test func completionKeepsTheEditsTheEditorSaved() async {
        let activeRepository = InMemoryActiveChallengeRepository()
        let completedRepository = InMemoryCompletedChallengeRepository()
        let sut = makeEditorStageCaptureFlowSUT(
            activeRepository: activeRepository, completedRepository: completedRepository
        )

        // What the editor writes while the capture flow is not looking.
        activeRepository.stored?.document = .fixture(
            texts: [TextItem(content: "my outfit")], stickers: [StickerItem(emoji: "✨")]
        )

        sut.completeChallenge()
        await sut.completionTask?.value

        #expect(completedRepository.stored.first?.document.textContents == ["my outfit"])
        #expect(completedRepository.stored.first?.document.stickerEmojis == ["✨"])
    }

    @Test func completeChallengeIsIdempotent() async {
        let completedRepository = InMemoryCompletedChallengeRepository()
        let sut = makeEditorStageCaptureFlowSUT(completedRepository: completedRepository)

        sut.completeChallenge()
        await sut.completionTask?.value
        sut.completeChallenge()
        await sut.completionTask?.value

        #expect(completedRepository.stored.count == 1)
    }

    @Test func completeChallengeWithoutPhotoRecordsNothing() async {
        let completedRepository = InMemoryCompletedChallengeRepository()
        let sut = makeCaptureFlowSUT(completedRepository: completedRepository)

        sut.completeChallenge()
        await sut.completionTask?.value

        #expect(completedRepository.stored.isEmpty)
        #expect(!sut.isCompleted)
    }
}
