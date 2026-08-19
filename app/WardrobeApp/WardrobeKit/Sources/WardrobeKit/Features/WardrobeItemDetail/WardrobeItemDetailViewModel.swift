import Foundation
import Observation

@MainActor
@Observable
public final class WardrobeItemDetailViewModel {
    public private(set) var item: WardrobeItem?
    private(set) var wears: [WearRecord] = []
    private(set) var similar: [SimilarItem] = []
    public private(set) var isDeleted = false

    private let itemID: UUID
    private let repository: WardrobeItemRepository
    private let thumbnails: GarmentThumbnailRepository

    init(
        itemID: UUID,
        repository: WardrobeItemRepository,
        thumbnails: GarmentThumbnailRepository
    ) {
        self.itemID = itemID
        self.repository = repository
        self.thumbnails = thumbnails
    }

    // MARK: Derived from the wear records

    var wearCount: Int {
        wears.count
    }

    var firstWornAt: Date? {
        wears.map(\.wornAt).min()
    }

    var lastWornAt: Date? {
        wears.map(\.wornAt).max()
    }

    // MARK: Loading

    public func load() {
        do {
            item = try repository.items().first { $0.id == itemID }
            wears = try repository.wears(for: itemID).sorted { $0.wornAt > $1.wornAt }
            similar = try loadSimilar()
        } catch {
            Log.report(error)
        }
    }

    private func loadSimilar() throws -> [SimilarItem] {
        let items = try repository.items()
        let categories = Dictionary(items.map { ($0.id, $0.category) }, uniquingKeysWith: { first, _ in first })
        guard let category = categories[itemID] else { return [] }

        let fingerprints = try repository.fingerprints()
        var best: [UUID: ItemMatch] = [:]
        for mine in fingerprints where mine.itemID == itemID {
            let candidates = ItemMatching.candidates(
                for: mine, category: category, among: fingerprints, categories: categories
            )
            for match in candidates where match.score > (best[match.itemID]?.score ?? 0) {
                best[match.itemID] = match
            }
        }

        return best.values
            .sorted { $0.score > $1.score }
            .compactMap { match in
                items.first { $0.id == match.itemID }.map { SimilarItem(item: $0, match: match) }
            }
    }

    func thumbnailData(for item: WardrobeItem) -> Data? {
        try? thumbnails.data(forFile: item.cutoutFile)
    }

    // MARK: Deleting

    public func delete() {
        guard let item else { return }
        do {
            try repository.delete(itemID: item.id)
            try? thumbnails.delete(file: item.cutoutFile)
            isDeleted = true
            Log.ui.info("Wardrobe: item deleted")
        } catch {
            Log.report(error)
        }
    }

    public func updateItem(name: String, description: String) {
        guard var updated = item else { return }
        updated.name = name
        updated.description = description
        updated.updatedAt = Date()

        do {
            try repository.update(updated)
            item = updated
            Log.ui.info("Wardrobe: item updated")
        } catch {
            Log.report(error)
        }
    }
}
