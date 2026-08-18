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
        activeRepository.stored?.draft = EditDraft(
            texts: [TextItem(content: "my outfit")], stickers: [StickerItem(emoji: "✨")]
        )

        sut.completeChallenge()
        await sut.completionTask?.value

        #expect(completedRepository.stored.first?.draft.texts.map(\.content) == ["my outfit"])
        #expect(completedRepository.stored.first?.draft.stickers.map(\.emoji) == ["✨"])
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
