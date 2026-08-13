import Foundation
import Testing
@testable import WardrobeKit

@MainActor
struct DevMenuViewModelTests {
    private func makeSUT(
        store: InMemoryActiveChallengeStore = InMemoryActiveChallengeStore(),
        completedStore: InMemoryCompletedChallengeStore = InMemoryCompletedChallengeStore(),
        photoStore: SpyPhotoStore = SpyPhotoStore()
    ) -> DevMenuViewModel {
        DevMenuViewModel(store: store, completedStore: completedStore, photoStore: photoStore)
    }

    private func makeCompletion(at date: Date, photoID: String = UUID().uuidString) -> CompletedChallenge {
        CompletedChallenge(
            card: ChallengeCard(prompt: "x"),
            photoID: photoID,
            draft: EditDraft(),
            completedAt: date
        )
    }

    private func makeActive(photoID: String?) -> ActiveChallenge {
        var challenge = ActiveChallenge(card: ChallengeCard(prompt: "x"), acceptedAt: .distantPast)
        challenge.photoID = photoID
        return challenge
    }

    @Test func resetTodayClearsCompletionActiveChallengeAndPhotos() {
        let store = InMemoryActiveChallengeStore()
        store.stored = makeActive(photoID: "active-photo")
        let completedStore = InMemoryCompletedChallengeStore()
        completedStore.stored = [makeCompletion(at: Date(), photoID: "done-photo")]
        let photoStore = SpyPhotoStore()
        let sut = makeSUT(store: store, completedStore: completedStore, photoStore: photoStore)

        sut.resetToday()

        #expect(completedStore.stored.isEmpty)
        #expect(store.stored == nil)
        #expect(photoStore.deleted.sorted() == ["active-photo", "done-photo"])
        #expect(sut.summary == DevStateSummary())
        #expect(sut.lastAction != nil)
    }

    @Test func resetTodayKeepsEarlierCompletions() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        let completedStore = InMemoryCompletedChallengeStore()
        completedStore.stored = [makeCompletion(at: yesterday, photoID: "old"), makeCompletion(at: Date())]
        let photoStore = SpyPhotoStore()
        let sut = makeSUT(completedStore: completedStore, photoStore: photoStore)

        sut.resetToday()

        #expect(completedStore.stored.map(\.photoID) == ["old"])
        #expect(!photoStore.deleted.contains("old"))
        #expect(sut.summary.completionCount == 1)
        #expect(!sut.summary.hasCompletedToday)
    }

    @Test func resetTodayIsSafeWhenNothingToReset() {
        let photoStore = SpyPhotoStore()
        let sut = makeSUT(photoStore: photoStore)

        sut.resetToday()

        #expect(photoStore.deleted.isEmpty)
        #expect(sut.summary == DevStateSummary())
    }

    @Test func summaryReflectsStoresAfterRefresh() {
        let store = InMemoryActiveChallengeStore()
        store.stored = makeActive(photoID: nil)
        let completedStore = InMemoryCompletedChallengeStore()
        completedStore.stored = [makeCompletion(at: Date())]
        let sut = makeSUT(store: store, completedStore: completedStore)

        sut.refresh()

        #expect(sut.summary == DevStateSummary(
            completionCount: 1,
            hasCompletedToday: true,
            hasActiveChallenge: true,
            activeHasPhoto: false
        ))
    }
}
