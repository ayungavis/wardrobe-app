import Foundation
import Testing
@testable import WardrobeKit

struct ChallengeCatalogTests {
    @Test func theMockDeckCarriesTheSeededCatalogIdentities() async throws {
        let first = try await MockChallengeRepository().fetchDailyDeck()
        let second = try await MockChallengeRepository().fetchDailyDeck()

        #expect(first.map(\.id) == second.map(\.id),
                "a random card id violates the card_id foreign key on every completion")
        let seeded = ["019205f0-0000-7000-8000-000000000002",
                      "019205f0-0000-7000-8000-000000000003",
                      "019205f0-0000-7000-8000-000000000004"].compactMap(UUID.init(uuidString:))
        #expect(first.map(\.id) == seeded,
                "the ids must match migrations/0009_curated_cards.sql or the server refuses them")
    }
}
