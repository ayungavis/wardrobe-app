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
