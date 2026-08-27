import CoreGraphics
import Testing
@testable import WardrobeKit

struct ZoomLayoutTests {
    @Test func nothingIsLaidOutBeforeTheScrollViewHasASize() {
        #expect(
            ZoomLayout.fitted(in: .zero, margin: 24) == .zero,
            "laying out against a zero bounds is what left the illustration invisible"
        )
    }

    @Test func theGarmentKeepsAMarginOnEverySide() {
        let fitted = ZoomLayout.fitted(in: CGSize(width: 390, height: 800), margin: 24)

        #expect(fitted == CGSize(width: 342, height: 752))
    }

    @Test func aMarginWiderThanTheScreenNeverProducesANegativeSize() {
        let fitted = ZoomLayout.fitted(in: CGSize(width: 20, height: 20), margin: 24)

        #expect(fitted == .zero, "a negative frame draws nothing and scrolls wrong")
    }

    @Test func contentSmallerThanTheScreenIsCentred() {
        let insets = ZoomLayout.centring(
            bounds: CGSize(width: 400, height: 900), content: CGSize(width: 300, height: 500)
        )

        #expect(insets == ZoomLayout.Insets(horizontal: 50, vertical: 200))
    }

    @Test func contentLargerThanTheScreenGetsNoInset() {
        let insets = ZoomLayout.centring(
            bounds: CGSize(width: 400, height: 900), content: CGSize(width: 900, height: 1800)
        )

        #expect(insets == ZoomLayout.Insets(horizontal: 0, vertical: 0), "an inset here would fight the pan")
    }
}
