import Foundation

enum OnboardingStep: Int, CaseIterable {
    case wardrobe
    case collage
    case firstChallenge

    var titleKey: String {
        "onboarding.\(self).title"
    }

    var symbolName: String {
        switch self {
        case .wardrobe: "tshirt.fill"
        case .collage: "sparkles.rectangle.stack.fill"
        case .firstChallenge: "flag.checkered"
        }
    }

    var next: OnboardingStep? {
        OnboardingStep(rawValue: rawValue + 1)
    }

    var previous: OnboardingStep? {
        OnboardingStep(rawValue: rawValue - 1)
    }
}
