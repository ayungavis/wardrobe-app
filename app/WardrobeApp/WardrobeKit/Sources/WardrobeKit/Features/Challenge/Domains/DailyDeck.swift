import Foundation

public struct DailyDeck: Equatable, Sendable {
    public let cards: [ChallengeCard]
    public let isCurated: Bool

    public init(cards: [ChallengeCard], isCurated: Bool) {
        self.cards = cards
        self.isCurated = isCurated
    }
}
