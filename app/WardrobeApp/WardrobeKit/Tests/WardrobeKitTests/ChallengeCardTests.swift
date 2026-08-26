import Foundation
import Testing
@testable import WardrobeKit

struct ChallengeCardTests {
    @Test func aCardStoredBeforeFreestyleExistedStillDecodes() throws {
        let stored = Data(#"{"id":"3F2504E0-4F89-11D3-9A0C-0305E82C3301","prompt":"Wear red"}"#.utf8)

        let card = try JSONDecoder().decode(ChallengeCard.self, from: stored)

        #expect(card.prompt == "Wear red")
        #expect(card.isFreestyle == false)
    }

    @Test func aFreestyleCardSurvivesARoundTrip() throws {
        let encoded = try JSONEncoder().encode(ChallengeCard.freestyle)

        let card = try JSONDecoder().decode(ChallengeCard.self, from: encoded)

        #expect(card == ChallengeCard.freestyle)
        #expect(card.isFreestyle)
    }

    @Test func bothFreestyleEntryPointsMintOneIdentity() {
        #expect(ChallengeCard.freestyle.id == ChallengeCard.freestyle.id)
        #expect(ChallengeCard.freestyle.isFreestyle)
    }
}

struct ChallengeCardOutfitTests {
    private func decode(_ json: String) throws -> ChallengeCard {
        try JSONDecoder().decode(ChallengeCard.self, from: Data(json.utf8))
    }

    @Test func aCardStoredBeforeTheOutfitFieldsExistedStillDecodes() throws {
        let card = try decode(#"{"id":"019205F0-0000-7000-8000-000000000002","prompt":"Wear red"}"#)

        #expect(card.title == nil)
        #expect(card.outfit == nil)
        #expect(card.prompt == "Wear red")
    }

    @Test func aCardWithAnOutfitSurvivesARoundTrip() throws {
        let top = UUID()
        let bottom = UUID()
        let card = ChallengeCard(
            title: "Unused Wear",
            prompt: "Mix and match",
            topItemID: top,
            bottomItemID: bottom
        )

        let restored = try JSONDecoder().decode(
            ChallengeCard.self,
            from: JSONEncoder().encode(card)
        )

        #expect(restored == card)
        #expect(restored.outfit?.top == top)
        #expect(restored.outfit?.bottom == bottom)
    }

    @Test func aHalfPairIsNotAnOutfit() {
        let card = ChallengeCard(prompt: "Mix", topItemID: UUID())

        #expect(card.outfit == nil,
                "the sentence names both garments, so one alone renders as text (FR-010)")
    }

    @Test func aCardEncodesNoNullOutfitKeys() throws {
        let encoded = try JSONEncoder().encode(ChallengeCard(prompt: "Wear red"))
        let keys = try Set(
            (JSONSerialization.jsonObject(with: encoded) as? [String: Any] ?? [:]).keys
        )

        #expect(
            keys == ["id", "prompt", "isFreestyle"],
            "the card is an opaque blob in three stores; null keys would rewrite all three for nothing"
        )
    }

    @Test func theFreestyleCardCarriesNoOutfit() {
        #expect(ChallengeCard.freestyle.outfit == nil)
        #expect(ChallengeCard.freestyle.title == nil)
    }
}
