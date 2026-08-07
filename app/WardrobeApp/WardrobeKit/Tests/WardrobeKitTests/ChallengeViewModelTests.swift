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
    @Test func loadSuccessSetsLoadedDeck() async {
        let repository = ControlledChallengeRepository()
        let sut = ChallengeViewModel(repository: repository)
        let cards = [ChallengeCard(prompt: "Wear something red.")]

        sut.load()
        #expect(sut.deck == .loading)

        await repository.resolveNext(with: .success(cards))
        await sut.loadTask?.value

        #expect(sut.deck == .loaded(cards))
    }

    @Test func loadFailureSetsTypedError() async {
        let repository = ControlledChallengeRepository()
        let sut = ChallengeViewModel(repository: repository)

        sut.load()
        await repository.resolveNext(with: .failure(URLError(.notConnectedToInternet)))
        await sut.loadTask?.value

        #expect(sut.deck == .failed(.network))
    }

    @Test func reloadCancelsStaleRequest() async {
        let repository = ControlledChallengeRepository()
        let sut = ChallengeViewModel(repository: repository)
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

    @Test func onAppearOnlyLoadsFromIdle() async {
        let repository = ControlledChallengeRepository()
        let sut = ChallengeViewModel(repository: repository)

        sut.onAppear()
        #expect(sut.deck == .loading)

        await repository.resolveNext(with: .success([]))
        await sut.loadTask?.value

        sut.onAppear()
        #expect(sut.deck == .loaded([]))
    }
}
