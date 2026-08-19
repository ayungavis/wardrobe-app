import Foundation
import Testing
@testable import WardrobeKit

/// What History puts inside the print (FR-096) — the composition the user
/// confirmed, not the capture behind it.
@MainActor
struct HistoryViewModelTests {
    private func makeSUT(
        completedRepository: InMemoryCompletedChallengeRepository = InMemoryCompletedChallengeRepository(),
        photoRepository: SpyPhotoRepository = SpyPhotoRepository(),
        previews: InMemoryCompletionPreviewRepository = InMemoryCompletionPreviewRepository()
    ) -> HistoryViewModel {
        HistoryViewModel(
            completedRepository: completedRepository,
            photoRepository: photoRepository,
            wardrobeRepository: InMemoryWardrobeItemRepository(),
            thumbnails: InMemoryGarmentThumbnailRepository(),
            previews: previews
        )
    }

    private func makeCompletion(previewFile: String? = nil) -> CompletedChallenge {
        var completion = CompletedChallenge(
            card: ChallengeCard(prompt: "x"), photoID: "photo-1",
            document: .fixture(photoID: "photo-1"), completedAt: Date()
        )
        completion.previewFile = previewFile
        return completion
    }

    @Test func storedPreviewIsUsedWithoutRendering() throws {
        let previews = InMemoryCompletionPreviewRepository()
        let file = try previews.save(Data([0xAA]), id: UUID())
        let completedRepository = InMemoryCompletedChallengeRepository()
        let completion = makeCompletion(previewFile: file)
        completedRepository.stored = [completion]
        let sut = makeSUT(completedRepository: completedRepository, previews: previews)
        sut.load()

        #expect(sut.previewData(for: completion) == Data([0xAA]))
    }

    /// Completions written before ✓ started storing a preview still have to be
    /// seen, so they are rendered on demand.
    @Test func aCompletionWithoutAPreviewIsRenderedOnDemand() async {
        let completedRepository = InMemoryCompletedChallengeRepository()
        let completion = makeCompletion()
        completedRepository.stored = [completion]
        let sut = makeSUT(completedRepository: completedRepository)
        sut.load()
        #expect(sut.previewData(for: completion) == nil)

        await sut.renderMissingPreview(for: completion)

        #expect(sut.previewData(for: completion) != nil)
    }

    /// Rendering is the expensive part, so a second pass over a card that
    /// already has its picture must not pay for it again.
    @Test func aSecondRenderPassIsSkipped() async throws {
        let previews = InMemoryCompletionPreviewRepository()
        let file = try previews.save(Data([0xAA]), id: UUID())
        let completedRepository = InMemoryCompletedChallengeRepository()
        let completion = makeCompletion(previewFile: file)
        completedRepository.stored = [completion]
        let sut = makeSUT(completedRepository: completedRepository, previews: previews)
        sut.load()

        await sut.renderMissingPreview(for: completion)

        // Still the stored bytes, not something freshly rasterised over them.
        #expect(sut.previewData(for: completion) == Data([0xAA]))
    }

    /// The on-demand renders are a cache, and a cache that outlives the list it
    /// describes is a leak.
    @Test func reloadingDropsTheRenderedCache() async {
        let completedRepository = InMemoryCompletedChallengeRepository()
        let completion = makeCompletion()
        completedRepository.stored = [completion]
        let sut = makeSUT(completedRepository: completedRepository)
        sut.load()
        await sut.renderMissingPreview(for: completion)
        #expect(sut.previewData(for: completion) != nil)

        sut.load()

        #expect(sut.previewData(for: completion) == nil)
    }
}
