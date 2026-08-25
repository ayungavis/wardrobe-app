import Foundation
import Observation

@MainActor
@Observable
public final class HistoryViewModel {
    public private(set) var state: Loadable<[CompletedChallenge]> = .idle

    private let completedRepository: CompletedChallengeRepository
    private(set) var syncStates: [UUID: SyncState] = [:]
    private(set) var openConflictCount = 0
    private let outbox: any OutboxRepository
    private let uploads: any MediaUploadRepository
    private let photoRepository: PhotoRepository
    private let wardrobeRepository: WardrobeItemRepository
    private let thumbnails: GarmentThumbnailRepository
    private let previews: CompletionPreviewRepository
    private var renderedPreviews: [UUID: Data] = [:]

    public init(
        completedRepository: CompletedChallengeRepository,
        outbox: any OutboxRepository,
        uploads: any MediaUploadRepository,
        photoRepository: PhotoRepository,
        wardrobeRepository: WardrobeItemRepository,
        thumbnails: GarmentThumbnailRepository,
        previews: CompletionPreviewRepository
    ) {
        self.completedRepository = completedRepository
        self.outbox = outbox
        self.uploads = uploads
        self.photoRepository = photoRepository
        self.wardrobeRepository = wardrobeRepository
        self.thumbnails = thumbnails
        self.previews = previews
    }

    public func load() {
        state = .loaded(completedRepository.load().sorted { $0.completedAt > $1.completedAt })
        refreshSyncStates()
        openConflictCount = ConflictCounting.openCount(
            wardrobe: wardrobeRepository, completions: completedRepository
        )
        renderedPreviews = [:]
    }

    public var completions: [CompletedChallenge] {
        guard case let .loaded(completions) = state else { return [] }
        return completions
    }

    public func completion(id: UUID) -> CompletedChallenge? {
        completions.first { $0.id == id }
    }

    public func previewData(for completion: CompletedChallenge) -> Data? {
        if let file = completion.previewFile, let data = try? previews.data(forFile: file) {
            return data
        }
        return renderedPreviews[completion.id]
    }

    public func renderMissingPreview(for completion: CompletedChallenge) async {
        guard previewData(for: completion) == nil else { return }

        var originals: [UUID: Data] = [:]
        for id in Set(completion.document.photoIDs) {
            originals[id] = try? photoRepository.loadOriginal(id: id)
        }
        guard let data = try? await ExportService.render(
            originals: originals, document: completion.document
        ) else {
            return
        }
        renderedPreviews[completion.id] = data
    }

    public func garmentsWorn(in completion: CompletedChallenge) -> [(item: WardrobeItem, wearCount: Int)] {
        do {
            let items = try wardrobeRepository.items()
            var results: [(WardrobeItem, Int)] = []

            for item in items {
                let wears = try wardrobeRepository.wears(for: item.id)
                let wasWornInThisCompletion = wears.contains { $0.completionID == completion.id }
                if wasWornInThisCompletion {
                    results.append((item, wears.count))
                }
            }
            return results
        } catch {
            Log.report(error)
            return []
        }
    }

    public func thumbnailData(for item: WardrobeItem) -> Data? {
        try? thumbnails.data(forFile: item.cutoutFile)
    }
}

// MARK: - Sync state (FR-061)

extension HistoryViewModel {
    func refreshSyncStates() {
        let mutations = (try? outbox.entries()) ?? []
        let rows = (try? uploads.entries()) ?? []
        var states: [UUID: SyncState] = [:]
        for completion in completions {
            states[completion.id] = SyncState.derive(
                queuedAt: completion.syncQueuedAt,
                mutation: mutations.first { $0.id == completion.id },
                mediaRows: rows.filter { $0.ownerID == completion.id }
            )
        }
        syncStates = states
    }

    func syncState(for completion: CompletedChallenge) -> SyncState {
        syncStates[completion.id] ?? .localOnly
    }
}
