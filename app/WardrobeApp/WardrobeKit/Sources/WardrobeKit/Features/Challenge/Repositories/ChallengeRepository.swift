import Foundation

public protocol ChallengeRepository: Sendable {
    func fetchDailyDeck() async throws -> [ChallengeCard]
}

// ponytail: mock deck until the backend exists; replace with the API-backed
// repository once services/ ships its first endpoint.
public struct MockChallengeRepository: ChallengeRepository {
    public init() {}

    public func fetchDailyDeck() async throws -> [ChallengeCard] {
        [
            ChallengeCard(
                id: Self.catalogID("019205f0-0000-7000-8000-000000000002"),
                prompt: "Today is a good day to wear something red."
            ),
            ChallengeCard(
                id: Self.catalogID("019205f0-0000-7000-8000-000000000003"),
                prompt: "Style your most comfortable shoes for going out."
            ),
            ChallengeCard(
                id: Self.catalogID("019205f0-0000-7000-8000-000000000004"),
                prompt: "Layer two pieces you have never worn together."
            ),
        ]
    }

    private static func catalogID(_ literal: String) -> UUID {
        // Type safety: compile-time-constant UUID literals mirroring
        // migrations/0009_curated_cards.sql; a typo fails the catalog test.
        // swiftlint:disable:next force_unwrapping
        UUID(uuidString: literal)!
    }
}
