import Foundation
import Testing
@testable import WardrobeKit

/// Repository whose responses are resolved manually, so tests control timing.
actor ControlledChallengeRepository: ChallengeRepository {
    private var continuations: [CheckedContinuation<[ChallengeCard], Error>] = []

    func fetchDailyDeck() async throws -> [ChallengeCard] {
        try await withCheckedThrowingContinuation { continuations.append($0) }
    }

    func resolveNext(with result: Result<[ChallengeCard], Error>) async {
        while continuations.isEmpty {
            await Task.yield()
        }
        continuations.removeFirst().resume(with: result)
    }
}

@MainActor
struct ChallengeViewModelTests {
    private func makeSUT(
        repository: ChallengeRepository = ControlledChallengeRepository(),
        store: ActiveChallengeStore = InMemoryActiveChallengeStore(),
        photoStore: PhotoStore = SpyPhotoStore()
    ) -> ChallengeViewModel {
        ChallengeViewModel(repository: repository, store: store, photoStore: photoStore)
    }

    // MARK: Deck loading

    @Test func loadSuccessSetsLoadedDeck() async {
        let repository = ControlledChallengeRepository()
        let sut = makeSUT(repository: repository)
        let cards = [ChallengeCard(prompt: "Wear something red.")]

        sut.load()
        #expect(sut.deck == .loading)

        await repository.resolveNext(with: .success(cards))
        await sut.loadTask?.value

        #expect(sut.deck == .loaded(cards))
    }

    @Test func loadFailureSetsTypedError() async {
        let repository = ControlledChallengeRepository()
        let sut = makeSUT(repository: repository)

        sut.load()
        await repository.resolveNext(with: .failure(URLError(.notConnectedToInternet)))
        await sut.loadTask?.value

        #expect(sut.deck == .failed(.network))
    }

    @Test func reloadCancelsStaleRequest() async {
        let repository = ControlledChallengeRepository()
        let sut = makeSUT(repository: repository)
        let stale = [ChallengeCard(prompt: "stale")]
        let latest = [ChallengeCard(prompt: "latest")]

        sut.load()
        let staleTask = sut.loadTask
        sut.load()

        await repository.resolveNext(with: .success(stale))
        await repository.resolveNext(with: .success(latest))
        await staleTask?.value
        await sut.loadTask?.value

        #expect(sut.deck == .loaded(latest))
    }

    // MARK: Accept (FR-011)

    @Test func acceptPersistsActiveChallengeAndPresentsFlow() {
        let store = InMemoryActiveChallengeStore()
        let sut = makeSUT(store: store)
        let card = ChallengeCard(prompt: "x")

        sut.accept(card)

        #expect(sut.activeChallenge?.card == card)
        #expect(store.stored?.card == card)
        #expect(sut.isCaptureFlowPresented)
    }

    @Test func acceptSameCardIsIdempotent() {
        let store = InMemoryActiveChallengeStore()
        let sut = makeSUT(store: store)
        let card = ChallengeCard(prompt: "x")

        sut.accept(card)
        let first = store.stored
        sut.isCaptureFlowPresented = false

        sut.accept(card)

        #expect(store.stored == first)
        #expect(sut.isCaptureFlowPresented)
    }

    @Test func acceptAnotherCardIsIgnoredWhileActive() {
        let store = InMemoryActiveChallengeStore()
        let sut = makeSUT(store: store)
        let first = ChallengeCard(prompt: "first")

        sut.accept(first)
        sut.isCaptureFlowPresented = false
        sut.accept(ChallengeCard(prompt: "second"))

        #expect(sut.activeChallenge?.card == first)
        #expect(!sut.isCaptureFlowPresented)
    }

    @Test func onAppearLoadsPersistedActiveChallenge() {
        let store = InMemoryActiveChallengeStore()
        store.stored = ActiveChallenge(card: ChallengeCard(prompt: "persisted"), acceptedAt: .distantPast)
        let sut = makeSUT(store: store)

        sut.onAppear()

        #expect(sut.activeChallenge?.card.prompt == "persisted")
    }

    // MARK: Abandon (FR-017)

    @Test func abandonWithoutDraftClearsImmediately() {
        let store = InMemoryActiveChallengeStore()
        let sut = makeSUT(store: store)
        sut.accept(ChallengeCard(prompt: "x"))

        sut.requestAbandon()

        #expect(!sut.isAbandonConfirmationPresented)
        #expect(sut.activeChallenge == nil)
        #expect(store.stored == nil)
    }

    @Test func abandonWithDraftRequiresConfirmationThenDeletesPhoto() throws {
        let store = InMemoryActiveChallengeStore()
        let photoStore = SpyPhotoStore()
        let sut = makeSUT(store: store, photoStore: photoStore)
        sut.accept(ChallengeCard(prompt: "x"))

        var active = try #require(store.stored)
        active.photoID = "11111111-2222-3333-4444-555555555555"
        store.stored = active
        sut.refreshActiveChallenge()

        sut.requestAbandon()
        #expect(sut.isAbandonConfirmationPresented)
        #expect(sut.activeChallenge != nil)

        sut.abandon()
        #expect(photoStore.deleted == ["11111111-2222-3333-4444-555555555555"])
        #expect(sut.activeChallenge == nil)
        #expect(store.stored == nil)
    }
}
