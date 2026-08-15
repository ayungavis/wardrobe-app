import Foundation
import Testing
@testable import WardrobeKit

@MainActor
struct WardrobeViewModelTests {
    @Test func loadReadsTheStoredItemsNewestFirst() throws {
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

        #expect(sut.items.map(\.id) == [newer.id, older.id])
    }

    @Test func thumbnailIsNilWhenTheImageIsMissing() {
        let thumbnails = InMemoryGarmentThumbnailRepository()
        let sut = WardrobeViewModel(thumbnails: thumbnails, repository: InMemoryWardrobeItemRepository())
        let item = WardrobeItem(category: .top, cutoutFile: "gone.png", createdAt: Date(), updatedAt: Date())

        #expect(sut.thumbnailData(for: item) == nil)
    }
}
