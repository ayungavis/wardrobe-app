import Foundation
import Testing
@testable import WardrobeKit

struct OnboardingStepTests {
    private func catalogueKeys() throws -> Set<String> {
        let url = try #require(Bundle.module.url(forResource: "Localizable", withExtension: "xcstrings"))
        let catalogue = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        let strings = try #require((catalogue as? [String: Any])?["strings"] as? [String: Any])
        return Set(strings.keys)
    }

    @Test func theStepsRunInTheOrderTheyAreShown() {
        #expect(OnboardingStep.allCases == [.wardrobe, .collage, .firstChallenge])
        #expect(OnboardingStep.wardrobe.previous == nil)
        #expect(OnboardingStep.firstChallenge.next == nil)
    }

    /// The last step swaps its paragraph for a call to action, so it is the one
    /// step with no description — and the only one.
    @Test func onlyTheLastStepHasNoDescription() {
        for step in OnboardingStep.allCases {
            #expect((step.descKey == nil) == (step == .firstChallenge))
        }
    }

    /// A key assembled at runtime cannot be checked by the compiler, and a miss
    /// puts the raw key on screen rather than failing. This is where it fails
    /// instead.
    @Test func everyKeyAStepAsksForExistsInTheCatalogue() throws {
        let keys = try catalogueKeys()

        for step in OnboardingStep.allCases {
            #expect(keys.contains(step.titleKey), "missing \(step.titleKey)")
            if let descKey = step.descKey {
                #expect(keys.contains(descKey), "missing \(descKey)")
            }
        }
    }

    @Test func everyStepNamesItsOwnPreview() {
        let images = OnboardingStep.allCases.map(\.image)

        #expect(Set(images).count == images.count)
        #expect(images.allSatisfy { !$0.isEmpty })
    }
}
