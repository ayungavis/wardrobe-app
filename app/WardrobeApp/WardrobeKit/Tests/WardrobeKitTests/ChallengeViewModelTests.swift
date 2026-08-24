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
        challengeRepository: ChallengeRepository = ControlledChallengeRepository(),
        activeRepository: ActiveChallengeRepository = InMemoryActiveChallengeRepository(),
        completedRepository: CompletedChallengeRepository = InMemoryCompletedChallengeRepository(),
        photoRepository: PhotoRepository = SpyPhotoRepository()
    ) -> ChallengeViewModel {
        ChallengeViewModel(
            challengeRepository: challengeRepository,
            activeRepository: activeRepository,
            completedRepository: completedRepository,
            photoRepository: photoRepository
        )
    }

    // MARK: Deck loading

    @Test func loadSuccessSetsLoadedDeck() async {
        let challengeRepository = ControlledChallengeRepository()
        let sut = makeSUT(challengeRepository: challengeRepository)
        let cards = [ChallengeCard(prompt: "Wear something red.")]

        sut.load()
        #expect(sut.deck == .loading)

        await challengeRepository.resolveNext(with: .success(cards))
        await sut.loadTask?.value

        #expect(sut.deck == .loaded(cards))
    }

    @Test func loadFailureSetsTypedError() async {
        let challengeRepository = ControlledChallengeRepository()
        let sut = makeSUT(challengeRepository: challengeRepository)

        sut.load()
        await challengeRepository.resolveNext(with: .failure(URLError(.notConnectedToInternet)))
        await sut.loadTask?.value

        #expect(sut.deck == .failed(.network))
    }

    @Test func reloadCancelsStaleRequest() async {
        let challengeRepository = ControlledChallengeRepository()
        let sut = makeSUT(challengeRepository: challengeRepository)
        let stale = [ChallengeCard(prompt: "stale")]
        let latest = [ChallengeCard(prompt: "latest")]

        sut.load()
        let staleTask = sut.loadTask
        sut.load()

        await challengeRepository.resolveNext(with: .success(stale))
        await challengeRepository.resolveNext(with: .success(latest))
        await staleTask?.value
        await sut.loadTask?.value

        #expect(sut.deck == .loaded(latest))
    }

    // MARK: Accept (FR-011)

    @Test func acceptPersistsActiveChallengeAndPresentsFlow() {
        let activeRepository = InMemoryActiveChallengeRepository()
        let sut = makeSUT(activeRepository: activeRepository)
        let card = ChallengeCard(prompt: "x")

        sut.accept(card)

        #expect(sut.activeChallenge?.card == card)
        #expect(activeRepository.stored?.card == card)
        #expect(sut.isCaptureFlowPresented)
    }

    @Test func acceptSameCardIsIdempotent() {
        let activeRepository = InMemoryActiveChallengeRepository()
        let sut = makeSUT(activeRepository: activeRepository)
        let card = ChallengeCard(prompt: "x")

        sut.accept(card)
        let first = activeRepository.stored
        sut.isCaptureFlowPresented = false

        sut.accept(card)

        #expect(activeRepository.stored == first)
        #expect(sut.isCaptureFlowPresented)
    }

    // MARK: Daily limit (FR-012)

    @Test func onAppearFlagsTodaysCompletionAndBlocksAccept() {
        let completedRepository = InMemoryCompletedChallengeRepository()
        completedRepository.stored = [makeCompletion(at: Date())]
        let activeRepository = InMemoryActiveChallengeRepository()
        let sut = makeSUT(activeRepository: activeRepository, completedRepository: completedRepository)

        sut.onAppear()
        sut.accept(ChallengeCard(prompt: "x"))

        #expect(sut.hasCompletedToday)
        #expect(sut.activeChallenge == nil)
        #expect(activeRepository.stored == nil)
        #expect(!sut.isCaptureFlowPresented)
    }

    @Test func yesterdaysCompletionReopensTheDeck() {
        let completedRepository = InMemoryCompletedChallengeRepository()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        completedRepository.stored = [makeCompletion(at: yesterday)]
        let sut = makeSUT(completedRepository: completedRepository)

        sut.onAppear()
        sut.accept(ChallengeCard(prompt: "x"))

        #expect(!sut.hasCompletedToday)
        #expect(sut.activeChallenge != nil)
    }

    private func makeCompletion(at date: Date) -> CompletedChallenge {
        CompletedChallenge(
            card: ChallengeCard(prompt: "done"),
            photoID: UUID.v7(),
            document: .fixture(),
            completedAt: date
        )
    }

    @Test func acceptAnotherCardIsIgnoredWhileActive() {
        let activeRepository = InMemoryActiveChallengeRepository()
        let sut = makeSUT(activeRepository: activeRepository)
        let first = ChallengeCard(prompt: "first")

        sut.accept(first)
        sut.isCaptureFlowPresented = false
        sut.accept(ChallengeCard(prompt: "second"))

        #expect(sut.activeChallenge?.card == first)
        #expect(!sut.isCaptureFlowPresented)
    }

    @Test func onAppearLoadsPersistedActiveChallenge() {
        let activeRepository = InMemoryActiveChallengeRepository()
        activeRepository.stored = ActiveChallenge(card: ChallengeCard(prompt: "persisted"), acceptedAt: .distantPast)
        let sut = makeSUT(activeRepository: activeRepository)

        sut.onAppear()

        #expect(sut.activeChallenge?.card.prompt == "persisted")
    }

    // MARK: Abandon (FR-017)

    @Test func abandonWithoutDraftClearsImmediately() {
        let activeRepository = InMemoryActiveChallengeRepository()
        let sut = makeSUT(activeRepository: activeRepository)
        sut.accept(ChallengeCard(prompt: "x"))

        sut.requestAbandon()

        #expect(!sut.isAbandonConfirmationPresented)
        #expect(sut.activeChallenge == nil)
        #expect(activeRepository.stored == nil)
    }

    @Test func abandonWithDraftRequiresConfirmationThenDeletesPhoto() throws {
        let activeRepository = InMemoryActiveChallengeRepository()
        let photoRepository = SpyPhotoRepository()
        let sut = makeSUT(activeRepository: activeRepository, photoRepository: photoRepository)
        sut.accept(ChallengeCard(prompt: "x"))

        var active = try #require(activeRepository.stored)
        active.photoID = id("11111111-2222-3333-4444-555555555555")
        activeRepository.stored = active
        sut.refreshActiveChallenge()

        sut.requestAbandon()
        #expect(sut.isAbandonConfirmationPresented)
        #expect(sut.activeChallenge != nil)

        sut.abandon()
        #expect(photoRepository.deleted == [id("11111111-2222-3333-4444-555555555555")])
        #expect(sut.activeChallenge == nil)
        #expect(activeRepository.stored == nil)
    }
}
