import CoreGraphics
import Testing
@testable import WardrobeKit

struct OnboardingSwipeTests {
    private let threshold = OnboardingSwipe.minimumDistance

    @Test func swipingLeftAdvances() {
        #expect(OnboardingSwipe.direction(for: CGSize(width: -120, height: 4)) == .next)
    }

    @Test func swipingRightGoesBack() {
        #expect(OnboardingSwipe.direction(for: CGSize(width: 120, height: -4)) == .back)
    }

    /// A drag shorter than the threshold is a tap that wandered, not a swipe.
    @Test func aShortDragIsIgnored() {
        #expect(OnboardingSwipe.direction(for: CGSize(width: -(threshold - 1), height: 0)) == nil)
        #expect(OnboardingSwipe.direction(for: CGSize(width: threshold - 1, height: 0)) == nil)
    }

    @Test func theThresholdItselfCounts() {
        #expect(OnboardingSwipe.direction(for: CGSize(width: -threshold, height: 0)) == .next)
        #expect(OnboardingSwipe.direction(for: CGSize(width: threshold, height: 0)) == .back)
    }

    /// Without this rule a scroll-like flick down and slightly sideways would
    /// change the step under the user's finger.
    @Test func aMostlyVerticalDragIsNotASwipe() {
        #expect(OnboardingSwipe.direction(for: CGSize(width: -80, height: 200)) == nil)
        #expect(OnboardingSwipe.direction(for: CGSize(width: 80, height: -200)) == nil)
    }

    @Test func standingStillDecidesNothing() {
        #expect(OnboardingSwipe.direction(for: .zero) == nil)
    }
}
