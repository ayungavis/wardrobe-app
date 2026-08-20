import Foundation

enum OnboardingStep: Int, CaseIterable {
    case wardrobe
    case collage
    case firstChallenge

    var titleKey: String {
        "onboarding.\(self).title"
    }

    var descKey: String? {
        self == .firstChallenge ? nil : "onboarding.\(self).description"
    }

    var image: String {
        switch self {
        case .wardrobe: "obPreview-1"
        case .collage: "obPreview-2"
        case .firstChallenge: "obPreview-3"
        }
    }

    var next: OnboardingStep? {
        OnboardingStep(rawValue: rawValue + 1)
    }

    var previous: OnboardingStep? {
        OnboardingStep(rawValue: rawValue - 1)
    }
}
