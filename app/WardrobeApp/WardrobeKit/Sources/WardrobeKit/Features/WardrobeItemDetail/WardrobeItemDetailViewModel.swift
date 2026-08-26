import Foundation
import Observation

@MainActor
@Observable
public final class WardrobeItemDetailViewModel {
    struct Detail: Equatable, Sendable {
        let item: WardrobeItem?
        let wears: [WearRecord]
        let similar: [SimilarItem]
    }

    public private(set) var isDeleted = false
    private(set) var pendingMerge: SimilarItem?
    private(set) var state: Loadable<Detail> = .idle
    private(set) var loadTask: Task<Void, Never>?

    private(set) var syncTask: Task<Void, Never>?

    private let itemID: UUID
    private let repository: WardrobeItemRepository
    private let thumbnails: GarmentThumbnailRepository
    private let syncNow: () async -> Void

    init(
        itemID: UUID,
        repository: WardrobeItemRepository,
        thumbnails: GarmentThumbnailRepository,
        syncNow: @escaping () async -> Void = {}
    ) {
        self.itemID = itemID
        self.repository = repository
        self.thumbnails = thumbnails
        self.syncNow = syncNow
    }

    // MARK: Derived from the wear records

    public var item: WardrobeItem? {
        detail?.item
    }

    var wears: [WearRecord] {
        detail?.wears ?? []
    }

    var similar: [SimilarItem] {
        detail?.similar ?? []
    }

    private var detail: Detail? {
        guard case let .loaded(detail) = state else { return nil }
        return detail
    }

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
        loadTask?.cancel()
        if case .loaded = state {} else {
            state = .loading
        }

        loadTask = Task {
            do {
                let item = try repository.items().first { $0.id == itemID }
                try Task.checkCancellation()
                let wears = try repository.wears(for: itemID).sorted { $0.wornAt > $1.wornAt }
                try Task.checkCancellation()
                let similar = try loadSimilar()
                try Task.checkCancellation()
                state = .loaded(Detail(item: item, wears: wears, similar: similar))
            } catch is CancellationError {
            } catch {
                Log.report(error)
                state = .failed(AppError(wrapping: error))
            }
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
        item.illustrationFile.flatMap { try? thumbnails.data(forFile: $0) }
            ?? (try? thumbnails.data(forFile: item.cutoutFile))
    }

    // MARK: Deleting

    public func delete() {
        guard let item else { return }
        do {
            try repository.delete(itemID: item.id)
            try? thumbnails.delete(file: item.cutoutFile)
            if let illustration = item.illustrationFile {
                try? thumbnails.delete(file: illustration)
            }
            isDeleted = true
            Log.ui.info("Wardrobe: item deleted")
            push()
        } catch {
            Log.report(error)
        }
    }

    func requestMerge(_ entry: SimilarItem) {
        pendingMerge = entry
    }

    func cancelMerge() {
        pendingMerge = nil
    }

    func confirmMerge() {
        guard let entry = pendingMerge else { return }
        pendingMerge = nil
        do {
            try repository.merge(winnerID: itemID, loserID: entry.item.id)
            try? thumbnails.delete(file: entry.item.cutoutFile)
            if let illustration = entry.item.illustrationFile {
                try? thumbnails.delete(file: illustration)
            }
            Log.ui.info("Wardrobe: items merged")
            push()
            load()
        } catch {
            Log.report(error)
        }
    }

    private func push() {
        syncTask?.cancel()
        syncTask = Task { [syncNow] in await syncNow() }
    }

    var isRegenerating: Bool {
        item.map { $0.status == .pending || $0.status == .processing } ?? false
    }

    func regenerateIllustration(note: String) {
        guard let item else { return }
        do {
            try repository.regenerateIllustration(itemID: item.id, note: note)
            Log.ui.info("Wardrobe: illustration asked for again")
            push()
            load()
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
            if let detail {
                state = .loaded(Detail(item: updated, wears: detail.wears, similar: detail.similar))
            }
            Log.ui.info("Wardrobe: item updated")
            push()
        } catch {
            Log.report(error)
        }
    }
}
