import Foundation
import Testing
@testable import WardrobeKit

@MainActor
struct WardrobeViewModelTests {
    @Test func loadReadsTheStoredItemsNewestFirst() async throws {
        let repository = InMemoryWardrobeItemRepository()
        let older = WardrobeItem(category: .top, cutoutFile: "a.png",
                                 createdAt: Date(timeIntervalSince1970: 1000),
                                 updatedAt: Date(timeIntervalSince1970: 1000))
        let newer = WardrobeItem(category: .bottom, cutoutFile: "b.png",
                                 createdAt: Date(timeIntervalSince1970: 2000),
                                 updatedAt: Date(timeIntervalSince1970: 2000))
        for item in [older, newer] {
            try repository.insert(item, fingerprint: nil, wear: WearRecord(itemID: item.id, wornAt: item.createdAt))
        }
        let sut = WardrobeViewModel(thumbnails: InMemoryGarmentThumbnailRepository(), repository: repository)

        sut.load()
        await sut.loadTask?.value

        #expect(sut.items.map(\.id) == [newer.id, older.id])
    }

    @Test func thumbnailIsNilWhenTheImageIsMissing() {
        let thumbnails = InMemoryGarmentThumbnailRepository()
        let sut = WardrobeViewModel(thumbnails: thumbnails, repository: InMemoryWardrobeItemRepository())
        let item = WardrobeItem(category: .top, cutoutFile: "gone.png", createdAt: Date(), updatedAt: Date())

        #expect(sut.thumbnailData(for: item) == nil)
    }

    /// The list is a snapshot, and renaming happens on another screen. If
    /// `load()` did not go back to storage the wardrobe would keep searching a
    /// copy that no longer matches what the user typed.
    @Test func loadPicksUpARenameMadeElsewhere() async throws {
        let repository = InMemoryWardrobeItemRepository()
        let item = WardrobeItem(category: .top, cutoutFile: "a.png", createdAt: Date(), updatedAt: Date())
        try repository.insert(item, fingerprint: nil, wear: WearRecord(itemID: item.id, wornAt: Date()))
        let sut = WardrobeViewModel(thumbnails: InMemoryGarmentThumbnailRepository(), repository: repository)
        sut.load()
        await sut.loadTask?.value

        var renamed = item
        renamed.name = "sleeve"
        renamed.description = "ayung hahaha"
        try repository.update(renamed)
        sut.load()
        await sut.loadTask?.value

        #expect(WardrobeSearch.results(in: sut.items, matching: "sleeve").map(\.id) == [item.id])
        #expect(WardrobeSearch.results(in: sut.items, matching: "ayung").map(\.id) == [item.id])
    }

    @Test func anEmptyWardrobeIsNotTheSameStateAsAFailedRead() async {
        let repository = InMemoryWardrobeItemRepository()
        let sut = WardrobeViewModel(thumbnails: InMemoryGarmentThumbnailRepository(), repository: repository)

        sut.load()
        await sut.loadTask?.value
        #expect(sut.state == .loaded(WardrobeViewModel.Wardrobe(items: [], wearCounts: [:])))

        repository.itemsError = AppError.unexpected
        sut.load()
        await sut.loadTask?.value
        #expect(sut.state == .failed(.unexpected))
        #expect(sut.items.isEmpty)
    }

    @Test func aReloadCancelsTheOneStillInFlight() async {
        let sut = WardrobeViewModel(
            thumbnails: InMemoryGarmentThumbnailRepository(),
            repository: InMemoryWardrobeItemRepository()
        )

        sut.load()
        let stale = sut.loadTask
        sut.load()

        #expect(stale?.isCancelled == true)
        await sut.loadTask?.value
        #expect(sut.loadTask?.isCancelled == false)
    }

    @Test func categoriesAndSearchAreDerivedByTheViewModel() async throws {
        let repository = InMemoryWardrobeItemRepository()
        let top = WardrobeItem(name: "Blue shirt", category: .top, cutoutFile: "a.png", createdAt: Date(), updatedAt: Date())
        let bottom = WardrobeItem(
            name: "Black jeans",
            category: .bottom,
            cutoutFile: "b.png",
            createdAt: Date(),
            updatedAt: Date()
        )
        for item in [top, bottom] {
            try repository.insert(item, fingerprint: nil, wear: nil)
        }
        let sut = WardrobeViewModel(thumbnails: InMemoryGarmentThumbnailRepository(), repository: repository)

        sut.load()
        await sut.loadTask?.value

        #expect(sut.items(in: .top).map(\.id) == [top.id])
        #expect(sut.items(in: .bottom).map(\.id) == [bottom.id])

        #expect(sut.isShowingSearchResults == false)
        sut.searchQuery = "jeans"
        #expect(sut.isShowingSearchResults)
        #expect(sut.searchResults.map(\.id) == [bottom.id])
    }
}
