import Foundation
import Testing
@testable import WardrobeKit

struct ChallengeCatalogTests {
    @Test func theCuratedDeckCarriesTheSeededCatalogIdentities() async throws {
        let first = try await CuratedChallengeRepository().fetchDailyDeck()
        let second = try await CuratedChallengeRepository().fetchDailyDeck()

        #expect(first.cards.map(\.id) == second.cards.map(\.id),
                "a random card id violates the card_id foreign key on every completion")
        let seeded = ["019205f0-0000-7000-8000-000000000002",
                      "019205f0-0000-7000-8000-000000000003",
                      "019205f0-0000-7000-8000-000000000004",
                      "019205f0-0000-7000-8000-000000000005",
                      "019205f0-0000-7000-8000-000000000006"].compactMap(UUID.init(uuidString:))
        #expect(first.cards.map(\.id) == seeded,
                "the ids must match the seeded catalog or the server refuses every completion")
    }

    @Test func theCuratedDeckIsCompleteAndTextOnly() async throws {
        let deck = try await CuratedChallengeRepository().fetchDailyDeck()

        #expect(deck.cards.count == 5,
                "a fallback that cannot fill a whole deck is not a fallback (FR-008)")
        #expect(deck.isCurated)
        #expect(deck.cards.allSatisfy { $0.title != nil })
        #expect(deck.cards.allSatisfy { $0.outfit == nil },
                "the fallback cannot ask for an illustration it has no way to resolve")
    }
}
