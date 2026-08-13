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
            ChallengeCard(prompt: "Today is a good day to wear something red."),
            ChallengeCard(prompt: "Style your most comfortable shoes for going out."),
            ChallengeCard(prompt: "Layer two pieces you have never worn together."),
        ]
    }
}
