import Foundation
import Testing
@testable import WardrobeKit

struct StickerSearchTests {
    @Test func searchingALetterFindsThatLetter() {
        let results = StickerCatalogue.search("m")
        let letters = results.filter { $0.category == .letter }

        #expect(!letters.isEmpty, "the alphabet is the biggest category and the one people search by name")
        #expect(
            letters.allSatisfy { $0.name == "M" },
            "letter_1 is Z: returning every letter would prove the glyph map is never read"
        )
    }

    @Test func searchingAWordFindsItsCategory() {
        let results = StickerCatalogue.search("flower")

        #expect(results.contains { $0.category == .flower })
        #expect(
            results.count >= 24,
            "numbered stickers carry no name of their own, so the category word is the only handle  a user has on them"
        )
    }

    @Test func searchMatchesIndonesianKeywords() {
        let results = StickerCatalogue.search("bunga")

        #expect(
            results.contains { $0.category == .flower },
            "the app ships en and id; keywords are data, so both languages search without needing  221 localisation keys"
        )
    }

    @Test func searchIsCaseInsensitive() {
        #expect(
            StickerCatalogue.search("FLOWER").map(\.id) == StickerCatalogue.search("flower").map(\.id)
        )
    }

    @Test func anEmptyQueryFindsNothingRatherThanEverything() {
        #expect(StickerCatalogue.search("").isEmpty)
        #expect(StickerCatalogue.search("   ").isEmpty)
    }

    @Test func everyImageStickerCarriesAnAssetAndACategory() {
        let images = StickerCatalogue.imageStickers

        #expect(images.count == 221)
        for sticker in images {
            guard case let .image(asset) = sticker.design else {
                Issue.record("\(sticker.id) is not an image sticker")
                continue
            }
            #expect(asset == sticker.id.replacingOccurrences(of: ".", with: "-"))
            #expect(sticker.category != nil)
        }
    }
}
