import Foundation
import Observation

/// The wardrobe grid. Filling it is the challenge loop's job (PRD §17) and the
/// dev-menu bulk scan's — this only reads.
@MainActor
@Observable
public final class WardrobeViewModel {
    public private(set) var items: [WardrobeItem] = []

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
            let missing = loaded.count { (try? thumbnails.data(forFile: $0.cutoutFile)) == nil }
            if missing > 0 {
                // Loud on purpose: a silent grey tile is how the stale-path bug
                // stayed invisible until someone reinstalled the app.
                Log.ui.error("Wardrobe: \(missing) of \(loaded.count) items have no image on disk")
            }
        } catch {
            Log.report(error)
        }
    }

    public func thumbnailData(for item: WardrobeItem) -> Data? {
        try? thumbnails.data(forFile: item.cutoutFile)
    }
}
