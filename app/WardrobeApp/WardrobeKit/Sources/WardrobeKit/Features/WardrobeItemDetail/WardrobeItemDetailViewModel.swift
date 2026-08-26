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
    private let completions: CompletedChallengeRepository?
    private let photos: PhotoRepository?
    private let syncNow: () async -> Void
    private let scanner: GarmentScanService?
    private let uploads: (any MediaUploadRepository)?

    private(set) var candidates: [ScannedGarment] = []
    private(set) var chosenCandidateID: UUID?
    private(set) var isScanningPhoto = false
    private(set) var scanTask: Task<Void, Never>?

    init(
        itemID: UUID,
        repository: WardrobeItemRepository,
        thumbnails: GarmentThumbnailRepository,
        completions: CompletedChallengeRepository? = nil,
        photos: PhotoRepository? = nil,
        syncNow: @escaping () async -> Void = {},
        scanner: GarmentScanService? = nil,
        uploads: (any MediaUploadRepository)? = nil
    ) {
        self.itemID = itemID
        self.repository = repository
        self.thumbnails = thumbnails
        self.completions = completions
        self.photos = photos
        self.syncNow = syncNow
        self.scanner = scanner
        self.uploads = uploads
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

    func thumbnailData(forFile file: String) -> Data? {
        try? thumbnails.data(forFile: file)
    }

    func cutoutData() -> Data? {
        item.flatMap { try? thumbnails.data(forFile: $0.cutoutFile) }
    }

    // ponytail: the newest wear names the outfit the item was cut from. An item
    // worn many times shows the latest photo, which is the one worth recognising.
    func originalPhotoData() -> Data? {
        guard let completions, let photos else { return nil }
        let stored = completions.load()
        for wear in wears.sorted(by: { $0.wornAt > $1.wornAt }) {
            guard let completionID = wear.completionID,
                  let completion = stored.first(where: { $0.id == completionID }),
                  let data = try? photos.loadOriginal(id: completion.photoID)
            else {
                continue
            }
            return data
        }
        return nil
    }

    private func push() {
        syncTask?.cancel()
        syncTask = Task { [syncNow] in await syncNow() }
    }

    var isRegenerating: Bool {
        item.map { $0.status == .pending || $0.status == .processing } ?? false
    }

    var chosenCandidate: ScannedGarment? {
        candidates.first { $0.id == chosenCandidateID }
    }

    func scanReferencePhoto(_ data: Data) {
        guard let scanner else { return }
        discardCandidates()
        isScanningPhoto = true
        scanTask = Task {
            defer { isScanningPhoto = false }
            do {
                let found = try await scanner.scan(photo: data)
                try Task.checkCancellation()
                candidates = found
                chosenCandidateID = found.count == 1 ? found[0].id : nil
            } catch is CancellationError {
            } catch {
                Log.report(error, logger: Log.ui)
            }
        }
    }

    func chooseCandidate(_ candidateID: UUID) {
        chosenCandidateID = candidateID
    }

    func discardCandidates(keeping kept: String? = nil) {
        for candidate in candidates where candidate.cutoutFile != kept {
            try? thumbnails.delete(file: candidate.cutoutFile)
        }
        candidates = []
        chosenCandidateID = nil
    }

    func regenerateIllustration(note: String) {
        guard let item else { return }
        do {
            try adoptChosenCutout(for: item)
            try repository.regenerateIllustration(itemID: item.id, note: note)
            Log.ui.info("Wardrobe: illustration asked for again")
            push()
            load()
        } catch {
            Log.report(error)
        }
    }

    private func adoptChosenCutout(for item: WardrobeItem) throws {
        guard let chosen = chosenCandidate else { return }
        let mediaID = UUID.v7()
        uploads?.stage(MediaUpload(
            id: mediaID, ownerID: item.id, kind: .cutout, contentType: "image/png",
            source: .thumbnailFile(chosen.cutoutFile), createdAt: Date()
        ))
        try repository.adoptCutout(itemID: item.id, path: chosen.cutoutFile, mediaID: mediaID)
        try? thumbnails.delete(file: item.cutoutFile)
        discardCandidates(keeping: chosen.cutoutFile)
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
