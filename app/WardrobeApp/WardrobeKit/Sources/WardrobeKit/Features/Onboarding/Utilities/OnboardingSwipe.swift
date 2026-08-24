import CoreGraphics

enum OnboardingSwipe {
    enum Direction {
        case next
        case back
    }

    static let minimumDistance: CGFloat = 50

    static func direction(for translation: CGSize) -> Direction? {
        guard abs(translation.width) >= minimumDistance,
              abs(translation.width) > abs(translation.height)
        else {
            return nil
        }
        return translation.width < 0 ? .next : .back
    }
}
