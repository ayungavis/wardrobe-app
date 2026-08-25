import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
public final class WardrobeViewModel {
    public struct Wardrobe: Equatable, Sendable {
        public let items: [WardrobeItem]
        public let wearCounts: [UUID: Int]
    }

    public enum SortOrder: String, CaseIterable, Sendable {
        case mostUsed
        case leastUsed

        public var title: LocalizedStringKey {
            switch self {
            case .mostUsed: "wardrobe.sort.mostUsed"
            case .leastUsed: "wardrobe.sort.leastUsed"
            }
        }
    }

    public private(set) var state: Loadable<Wardrobe> = .idle
    public var sortOrder: SortOrder = .mostUsed
    public var searchQuery = ""

    private let thumbnails: GarmentThumbnailRepository
    private let repository: WardrobeItemRepository
    private(set) var loadTask: Task<Void, Never>?

    private(set) var pendingSyncCount = 0
    private(set) var failedSyncCount = 0
    private(set) var openConflictCount = 0
    private let outbox: (any OutboxRepository)?
    private let completions: CompletedChallengeRepository?

    public init(
        thumbnails: GarmentThumbnailRepository,
        repository: WardrobeItemRepository,
        outbox: (any OutboxRepository)? = nil,
        completions: CompletedChallengeRepository? = nil
    ) {
        self.thumbnails = thumbnails
        self.repository = repository
        self.outbox = outbox
        self.completions = completions
    }

    public func load() {
        refreshSyncCounts()
        openConflictCount = ConflictCounting.openCount(wardrobe: repository, completions: completions)
        loadTask?.cancel()
        if case .loaded = state {} else {
            state = .loading
        }

        loadTask = Task {
            do {
                let items = try repository.items()
                try Task.checkCancellation()

                var counts: [UUID: Int] = [:]
                for item in items {
                    counts[item.id] = try repository.wears(for: item.id).count
                }
                try Task.checkCancellation()

                let missing = items.count { (try? thumbnails.data(forFile: $0.cutoutFile)) == nil }
                if missing > 0 {
                    Log.ui.error("Wardrobe: \(missing) of \(items.count) items have no image on disk")
                }
                state = .loaded(Wardrobe(items: items, wearCounts: counts))
            } catch is CancellationError {
            } catch {
                Log.report(error)
                state = .failed(AppError(wrapping: error))
            }
        }
    }

    public var items: [WardrobeItem] {
        guard case let .loaded(wardrobe) = state else { return [] }
        return wardrobe.items
    }

    public var isShowingSearchResults: Bool {
        !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty
    }

    public var searchResults: [WardrobeItem] {
        WardrobeSearch.results(in: items, matching: searchQuery)
    }

    public func items(in category: GarmentCategory) -> [WardrobeItem] {
        sorted(items.filter { $0.category == category })
    }

    public func sorted(_ items: [WardrobeItem]) -> [WardrobeItem] {
        switch sortOrder {
        case .mostUsed: items.sorted { wearCount(for: $0) > wearCount(for: $1) }
        case .leastUsed: items.sorted { wearCount(for: $0) < wearCount(for: $1) }
        }
    }

    public func thumbnailData(for item: WardrobeItem) -> Data? {
        try? thumbnails.data(forFile: item.cutoutFile)
    }

    public func wearCount(for item: WardrobeItem) -> Int {
        guard case let .loaded(wardrobe) = state else { return 0 }
        return wardrobe.wearCounts[item.id] ?? 0
    }
}

// MARK: - Grouped sync state (FR-061)

extension WardrobeViewModel {
    // ponytail: grouped, not per record — item mutations queue under random ids,
    // so tracing one to one item means parsing payloads. FR-061 allows a group.
    func refreshSyncCounts() {
        let entries = ((try? outbox?.entries()) ?? []).filter {
            $0.name == "upsertItem" || $0.name == "deleteItem"
        }
        pendingSyncCount = entries.count { $0.state == .pending }
        failedSyncCount = entries.count { $0.state == .failed }
    }

    func retryFailedSync() {
        try? outbox?.retryFailed(at: Date())
        refreshSyncCounts()
    }
}
