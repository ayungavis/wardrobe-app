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

    public init(thumbnails: GarmentThumbnailRepository, repository: WardrobeItemRepository) {
        self.thumbnails = thumbnails
        self.repository = repository
    }

    public func load() {
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
