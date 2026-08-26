import Foundation
import Testing
@testable import WardrobeKit

private struct StubChallengeRepository: ChallengeRepository {
    let deck: DailyDeck

    func fetchDailyDeck() async throws -> DailyDeck {
        deck
    }
}

private struct FailingChallengeRepository: ChallengeRepository {
    let error: any Error

    func fetchDailyDeck() async throws -> DailyDeck {
        throw error
    }
}

struct ChallengeFallbackTests {
    private let curated = CuratedChallengeRepository()

    private func card(_ prompt: String) -> ChallengeCard {
        ChallengeCard(prompt: prompt)
    }

    @Test func aFailingServerDeckFallsBackToTheCuratedDeck() async throws {
        let sut = FallbackChallengeRepository(
            primary: FailingChallengeRepository(error: URLError(.notConnectedToInternet)),
            fallback: curated
        )

        let deck = try await sut.fetchDailyDeck()

        #expect(deck.cards.count == 5)
        #expect(deck.isCurated, "FR-008 turns a failure into a complete deck, never an error screen")
    }

    @Test func anEmptyServerDeckFallsBackToTheCuratedDeck() async throws {
        let sut = FallbackChallengeRepository(
            primary: StubChallengeRepository(deck: DailyDeck(cards: [], isCurated: false)),
            fallback: curated
        )

        let deck = try await sut.fetchDailyDeck()

        #expect(deck.cards.count == 5,
                "a deck that has not been generated yet arrives as a successful, empty 200")
        #expect(deck.isCurated)
    }

    @Test func aShortServerDeckIsKeptAsIs() async throws {
        let server = DailyDeck(cards: [card("one"), card("two")], isCurated: false)
        let sut = FallbackChallengeRepository(
            primary: StubChallengeRepository(deck: server),
            fallback: curated
        )

        let deck = try await sut.fetchDailyDeck()

        #expect(deck.cards.count == 2,
                "the server owns the deck size; padding it mixes generated and curated silently")
        #expect(!deck.isCurated)
    }

    @Test func cancellationIsNotSwallowedAsAFallback() async {
        let sut = FallbackChallengeRepository(
            primary: FailingChallengeRepository(error: CancellationError()),
            fallback: curated
        )

        await #expect(throws: CancellationError.self) {
            _ = try await sut.fetchDailyDeck()
        }
    }
}
