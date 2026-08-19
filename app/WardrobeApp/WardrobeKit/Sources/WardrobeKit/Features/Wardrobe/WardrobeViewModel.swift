import Foundation
import Observation

@MainActor
@Observable
public final class WardrobeViewModel {
    public private(set) var items: [WardrobeItem] = []
    public private(set) var wearCounts: [UUID: Int] = [:]

    private let thumbnails: GarmentThumbnailRepository
    private let repository: WardrobeItemRepository

    public init(thumbnails: GarmentThumbnailRepository, repository: WardrobeItemRepository) {
        self.thumbnails = thumbnails
        self.repository = repository
    }

    public func load() {
        do {
            let loaded = try repository.items()
            items = loaded

            var counts: [UUID: Int] = [:]
            for item in loaded {
                counts[item.id] = try repository.wears(for: item.id).count
            }
            wearCounts = counts

            let missing = loaded.count { (try? thumbnails.data(forFile: $0.cutoutFile)) == nil }
            if missing > 0 {
                Log.ui.error("Wardrobe: \(missing) of \(loaded.count) items have no image on disk")
            }
        } catch {
            Log.report(error)
        }
    }

    public func thumbnailData(for item: WardrobeItem) -> Data? {
        try? thumbnails.data(forFile: item.cutoutFile)
    }

    public func wearCount(for item: WardrobeItem) -> Int {
        wearCounts[item.id] ?? 0
    }
}
