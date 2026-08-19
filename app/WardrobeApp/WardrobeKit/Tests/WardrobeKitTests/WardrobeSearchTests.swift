import Foundation
import Testing
@testable import WardrobeKit

struct WardrobeSearchTests {
    private func makeItem(name: String, description: String = "") -> WardrobeItem {
        WardrobeItem(
            name: name,
            description: description,
            category: .top,
            cutoutFile: "\(UUID().uuidString).png",
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    private var items: [WardrobeItem] {
        [
            makeItem(name: "Kemeja", description: "linen biru"),
            makeItem(name: "Kaós Polos", description: "putih"),
            makeItem(name: "Denim Jacket", description: "faded blue"),
        ]
    }

    @Test func anEmptyQueryReturnsEverythingUntouched() {
        let items = items

        #expect(WardrobeSearch.results(in: items, matching: "").map(\.id) == items.map(\.id))
    }

    @Test func aQueryOfOnlySpacesIsTreatedAsEmpty() {
        #expect(WardrobeSearch.results(in: items, matching: "   ").count == items.count)
    }

    @Test func matchingIgnoresCase() {
        let found = WardrobeSearch.results(in: items, matching: "DENIM")

        #expect(found.map(\.name) == ["Denim Jacket"])
    }

    /// People type without the accent far more often than with it.
    @Test func matchingIgnoresDiacritics() {
        let found = WardrobeSearch.results(in: items, matching: "kaos")

        #expect(found.map(\.name) == ["Kaós Polos"])
    }

    @Test func theDescriptionIsSearchedToo() {
        let found = WardrobeSearch.results(in: items, matching: "linen")

        #expect(found.map(\.name) == ["Kemeja"])
    }

    /// The reason the query is split at all: one word lives in the name and the
    /// other in the description, so a plain substring match would find nothing.
    @Test func everyWordMayComeFromADifferentField() {
        let found = WardrobeSearch.results(in: items, matching: "kemeja biru")

        #expect(found.map(\.name) == ["Kemeja"])
    }

    @Test func oneMissingWordDropsTheItemEvenWhenTheRestMatch() {
        #expect(WardrobeSearch.results(in: items, matching: "kemeja merah").isEmpty)
    }

    @Test func nothingMatchingIsEmptyRatherThanEverything() {
        #expect(WardrobeSearch.results(in: items, matching: "sepatu").isEmpty)
    }
}
