import Foundation
import Observation

/// What one wardrobe item is, how often it has been worn, and what else in the
/// wardrobe looks like it (PRD FR-036).
@MainActor
@Observable
public final class WardrobeItemDetailViewModel {
    public private(set) var item: WardrobeItem?
    /// Sorted newest first here rather than trusting the repository: the
    /// protocol only promises an order for `items()`, and a screen that quietly
    /// depends on an undocumented one breaks the day another implementation
    /// appears.
    private(set) var wears: [WearRecord] = []
    private(set) var similar: [SimilarItem] = []
    /// Set once the row is gone, so the view can close itself.
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

    // Computed rather than stored: a second copy of these could disagree with
    // the records they came from.

    var wearCount: Int {
        wears.count
    }

    /// Nil when the item has never been worn — never a fabricated date (FR-023).
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

    /// Runs the same matcher the review drawer uses, over every fingerprint this
    /// item has accumulated, and keeps each candidate's best score.
    ///
    /// Often empty, and that is a real answer rather than a failure: nothing in
    /// the wardrobe cleared the similarity threshold.
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

    /// Rows first, file second — the same order as the dev-menu reset, so a
    /// failure halfway cannot leave a row pointing at an image that is gone.
    ///
    /// A cut-out that has already vanished is not an error: the item still needs
    /// to go, and refusing would strand it forever.
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
