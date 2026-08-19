import Testing
@testable import WardrobeKit

/// The card's proportions, kept out of `body` so they can be checked rather
/// than eyeballed.
struct HistoryPolaroidGeometryTests {
    /// Three sides equal, and the lip much deeper — that is what makes it read
    /// as a print rather than a plain framed photo.
    @Test func theLipIsFarDeeperThanTheBorder() {
        #expect(HistoryPolaroidGeometry.bottomLip > HistoryPolaroidGeometry.padding * 5)
    }

    /// The window is the story canvas, so nothing the user composed is cropped
    /// away — that is the whole point of showing the edit instead of the photo.
    @Test func theWindowMatchesTheStoryCanvas() {
        let ratio = HistoryPolaroidGeometry.windowWidth / HistoryPolaroidGeometry.windowHeight
        #expect(abs(ratio - StoryCanvas.aspectRatio) < 0.0001)
    }

    /// The window plus a border on each side is the whole card width — no
    /// overhang, and no unexplained gap.
    @Test func theWindowAndItsTwoBordersSpanTheCard() {
        let span = HistoryPolaroidGeometry.windowWidth + HistoryPolaroidGeometry.padding * 2
        #expect(abs(span - 1) < 0.0001)
    }

    /// Card height is border + window + lip; the aspect ratio has to be its
    /// reciprocal or the card clips its own contents.
    @Test func theCardIsAsTallAsItsPartsAddUpTo() {
        let height = HistoryPolaroidGeometry.padding
            + HistoryPolaroidGeometry.windowHeight
            + HistoryPolaroidGeometry.bottomLip
        #expect(abs(HistoryPolaroidGeometry.cardAspectRatio - 1 / height) < 0.0001)
        // Portrait, and taller than it is wide by a good margin.
        #expect(HistoryPolaroidGeometry.cardAspectRatio < 0.6)
    }
}
