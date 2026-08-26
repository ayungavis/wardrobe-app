import Foundation
import Testing
@testable import WardrobeKit

/// Repository whose responses are resolved manually, so tests control timing.
actor ControlledChallengeRepository: ChallengeRepository {
    private var waitingFetches: [CheckedContinuation<DailyDeck, Error>] = []
    private var pendingResults: [Result<DailyDeck, Error>] = []
    private(set) var fetches = 0

    func fetchDailyDeck() async throws -> DailyDeck {
        fetches += 1
        if !pendingResults.isEmpty {
            return try pendingResults.removeFirst().get()
        }
        return try await withCheckedThrowingContinuation { waitingFetches.append($0) }
    }

    func resolveNext(cards: [ChallengeCard], isCurated: Bool = false) async {
        await resolveNext(with: .success(DailyDeck(cards: cards, isCurated: isCurated)))
    }

    func resolveNext(with result: Result<DailyDeck, Error>) async {
        if waitingFetches.isEmpty {
            pendingResults.append(result)
        } else {
            waitingFetches.removeFirst().resume(with: result)
        }
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

        await challengeRepository.resolveNext(cards: cards)
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

        await challengeRepository.resolveNext(cards: stale)
        await challengeRepository.resolveNext(cards: latest)
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

@MainActor
struct ChallengeDeckRefreshTests {
    private let jakarta = TimeZone(identifier: "Asia/Jakarta") ?? .gmt

    private func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = jakarta
        return calendar
    }

    private func makeSUT(
        repository: ControlledChallengeRepository,
        completedRepository: CompletedChallengeRepository = InMemoryCompletedChallengeRepository(),
        clock: @escaping @Sendable () -> Date
    ) -> ChallengeViewModel {
        ChallengeViewModel(
            challengeRepository: repository,
            activeRepository: InMemoryActiveChallengeRepository(),
            completedRepository: completedRepository,
            photoRepository: SpyPhotoRepository(),
            calendar: calendar(),
            now: clock
        )
    }

    private func card(_ prompt: String) -> ChallengeCard {
        ChallengeCard(prompt: prompt)
    }

    @Test func aDeckLoadedYesterdayIsRefetchedOnForeground() async {
        let repository = ControlledChallengeRepository()
        nonisolated(unsafe) var stamp = Date(timeIntervalSince1970: 1_787_000_000)
        let sut = makeSUT(repository: repository) { stamp }

        sut.onAppear()
        await repository.resolveNext(cards: [card("yesterday")])
        await sut.loadTask?.value

        stamp = stamp.addingTimeInterval(60 * 60 * 24)
        sut.refreshForForeground()
        await repository.resolveNext(cards: [card("today")])
        await sut.loadTask?.value

        #expect(await repository.fetches == 2, "a deck loaded yesterday is not today's deck")
        if case let .loaded(cards) = sut.deck {
            #expect(cards.map(\.prompt) == ["today"])
        } else {
            Issue.record("the refetched deck must be the loaded one")
        }
    }

    @Test func aDeckLoadedTodayIsNotRefetchedOnForeground() async {
        let repository = ControlledChallengeRepository()
        let stamp = Date(timeIntervalSince1970: 1_787_000_000)
        let sut = makeSUT(repository: repository) { stamp }

        sut.onAppear()
        await repository.resolveNext(cards: [card("today")])
        await sut.loadTask?.value

        sut.refreshForForeground()

        #expect(await repository.fetches == 1,
                "foregrounding all day must not re-ask for a deck that cannot have changed")
    }

    @Test func aCuratedFallbackIsRetriedOnTheNextForeground() async {
        let repository = ControlledChallengeRepository()
        let stamp = Date(timeIntervalSince1970: 1_787_000_000)
        let sut = makeSUT(repository: repository) { stamp }

        sut.onAppear()
        await repository.resolveNext(cards: [card("curated")], isCurated: true)
        await sut.loadTask?.value

        sut.refreshForForeground()
        await repository.resolveNext(cards: [card("generated")])
        await sut.loadTask?.value

        #expect(await repository.fetches == 2,
                "a fallback deck pins no day, so the real one is asked for again")
        #expect(!sut.isShowingCuratedDeck)
    }

    @Test func aRegeneratedDeckIsPickedUpTheSameDay() async {
        let repository = ControlledChallengeRepository()
        let stamp = Date(timeIntervalSince1970: 1_787_000_000)
        let sut = makeSUT(repository: repository) { stamp }

        sut.onAppear()
        await repository.resolveNext(cards: [card("before")])
        await sut.loadTask?.value

        sut.reloadDeck()
        await repository.resolveNext(cards: [card("after")])
        await sut.loadTask?.value

        #expect(await repository.fetches == 2,
                "the day key that spares a good deck from being refetched must not also strand a regenerated one")
        if case let .loaded(cards) = sut.deck {
            #expect(cards.map(\.prompt) == ["after"])
        } else {
            Issue.record("the regenerated deck must be the loaded one")
        }
    }

    @Test func dayRolloverAlsoReopensTheDeckAfterYesterdaysCompletion() async {
        let repository = ControlledChallengeRepository()
        nonisolated(unsafe) var stamp = Date(timeIntervalSince1970: 1_787_000_000)
        let completed = InMemoryCompletedChallengeRepository()
        completed.stored = [
            CompletedChallenge(
                card: card("done"),
                photoID: UUID(),
                document: EditorDocument(id: UUID(), layers: []),
                completedAt: stamp
            ),
        ]
        let sut = makeSUT(repository: repository, completedRepository: completed) { stamp }

        sut.onAppear()
        await repository.resolveNext(cards: [card("today")])
        await sut.loadTask?.value
        #expect(sut.hasCompletedToday)

        stamp = stamp.addingTimeInterval(60 * 60 * 24)
        sut.refreshForForeground()
        await repository.resolveNext(cards: [card("tomorrow")])
        await sut.loadTask?.value

        #expect(!sut.hasCompletedToday,
                "the daily gate rolls over with the clock the deck reads, not the wall clock")
    }
}
