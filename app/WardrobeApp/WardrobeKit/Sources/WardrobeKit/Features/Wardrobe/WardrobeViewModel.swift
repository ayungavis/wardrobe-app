import CoreGraphics
import Foundation
import Observation

@MainActor
@Observable
public final class WardrobeViewModel {
    public private(set) var items: [WardrobeItem] = []
    public private(set) var isScanning = false
    /// 0...1, drives the button's label while a batch is running.
    public private(set) var scanProgress: Double = 0
    /// Garments waiting for the user to confirm what they are. Nothing reaches
    /// the wardrobe until they do (FR-029).
    public private(set) var pendingReview: [ScannedGarment] = []

    private var processedPhotoIDs: Set<String> = []
    private let segmentation: GarmentSegmentationService
    private let thumbnails: GarmentThumbnailRepository
    private let repository: WardrobeItemRepository

    public init(
        segmentation: GarmentSegmentationService,
        thumbnails: GarmentThumbnailRepository,
        repository: WardrobeItemRepository
    ) {
        self.segmentation = segmentation
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

    public func thumbnailData(forFile file: String) -> Data? {
        try? thumbnails.data(forFile: file)
    }

    public func thumbnailData(forItemID itemID: UUID) -> Data? {
        guard let item = items.first(where: { $0.id == itemID }) else { return nil }
        return thumbnailData(for: item)
    }

    /// Each entry is a stable identifier plus the photo's bytes. Photos whose
    /// identifier was processed before are skipped.
    public func process(_ photos: [(id: String, data: Data)]) async {
        isScanning = true
        defer { isScanning = false }

        let fresh = photos.filter { !processedPhotoIDs.contains($0.id) }
        Log.ui.info("Wardrobe scan: \(fresh.count) new of \(photos.count) selected")
        guard !fresh.isEmpty else { return }

        // Loaded once per batch: the whole matching index is small enough to
        // hold, and re-reading it per garment would be wasteful.
        let known = (try? repository.fingerprints()) ?? []
        let categories = Dictionary(
            (try? repository.items())?.map { ($0.id, $0.category) } ?? [],
            uniquingKeysWith: { first, _ in first }
        )

        for (index, photo) in fresh.enumerated() {
            scanProgress = Double(index) / Double(fresh.count)
            process(photo, known: known, categories: categories)
        }
        scanProgress = 1
    }

    // MARK: Review

    /// The queue's only entry point: `process(_:)` stages one garment at a time,
    /// and tests stage a batch so confirmation can be exercised without a model.
    func stageForReview(_ garments: [ScannedGarment]) {
        pendingReview.append(contentsOf: garments)
    }

    public func choose(_ decision: ScannedGarment.Decision, for garmentID: UUID) {
        guard let index = pendingReview.firstIndex(where: { $0.id == garmentID }) else { return }
        pendingReview[index].decision = decision
    }

    /// Writes every confirmed decision, then clears the queue.
    public func confirmReview() {
        for garment in pendingReview {
            do {
                switch garment.decision {
                case .new:
                    try insert(garment)
                case let .existing(itemID):
                    try merge(garment, into: itemID)
                }
            } catch {
                Log.report(error)
            }
        }
        pendingReview = []
        load()
    }

    /// Nothing is written, and the cut-outs written during the scan are removed
    /// so a dismissed sheet does not leak files.
    public func cancelReview() {
        for garment in pendingReview {
            try? thumbnails.delete(file: garment.cutoutFile)
        }
        pendingReview = []
    }

    private func insert(_ garment: ScannedGarment) throws {
        let now = Date()
        let item = WardrobeItem(
            id: garment.id,
            category: garment.category,
            cutoutFile: garment.cutoutFile,
            createdAt: now,
            updatedAt: now
        )
        try repository.insert(
            item,
            fingerprint: garment.fingerprint,
            wear: WearRecord(itemID: garment.id, wornAt: now)
        )
    }

    private func merge(_ garment: ScannedGarment, into itemID: UUID) throws {
        // The fingerprint is re-pointed at the item it belongs to: an item owns
        // one per confirmed wear, and that set is what makes matching improve.
        let fingerprint = ItemFingerprint(
            itemID: itemID,
            version: garment.fingerprint.version,
            colorLab: garment.fingerprint.colorLab,
            aspectRatio: garment.fingerprint.aspectRatio,
            featurePrint: garment.fingerprint.featurePrint,
            maskQuality: garment.fingerprint.maskQuality,
            createdAt: Date()
        )
        try repository.recordWear(WearRecord(itemID: itemID, wornAt: Date()), fingerprint: fingerprint)
        try thumbnails.delete(file: garment.cutoutFile)
    }

    private func process(
        _ photo: (id: String, data: Data),
        known: [ItemFingerprint],
        categories: [UUID: GarmentCategory]
    ) {
        guard let image = ImageDecoding.downsampledImage(from: photo.data, maxPixel: 2048) else {
            Log.ui.error("Wardrobe scan: undecodable photo")
            return
        }

        do {
            guard let result = try segmentation.segment(image) else { return }
            for (category, cutout) in segmentation.cutouts(from: result) {
                try store(category: category, cutout: cutout, known: known, categories: categories)
            }
            processedPhotoIDs.insert(photo.id)
        } catch {
            Log.report(error)
        }
    }

    /// Queues a decision instead of writing one: the user confirms first.
    private func store(
        category: GarmentCategory,
        cutout: GarmentCutout,
        known: [ItemFingerprint],
        categories: [UUID: GarmentCategory]
    ) throws {
        let id = UUID()
        let print = fingerprint(for: id, cutout: cutout, at: Date())
        let matches = ItemMatching.candidates(
            for: print, category: category, among: known, categories: categories
        )
        Log.ui.info("Match: \(matches.count) candidates, best \(matches.first?.score ?? 0)")

        try stageForReview([ScannedGarment(
            id: id,
            category: category,
            cutoutFile: thumbnails.save(cutout.image, id: id),
            fingerprint: print,
            matches: matches,
            decision: ScannedGarment.defaultDecision(for: matches)
        )])
    }

    private func fingerprint(for itemID: UUID, cutout: GarmentCutout, at date: Date) -> ItemFingerprint {
        ItemFingerprint(
            itemID: itemID,
            version: GarmentFingerprinting.version,
            colorLab: GarmentFingerprinting.colorSignature(of: cutout.image),
            aspectRatio: GarmentFingerprinting.aspectRatio(of: cutout.image),
            featurePrint: GarmentFingerprinting.featurePrint(of: cutout.image),
            maskQuality: cutout.maskQuality,
            createdAt: date
        )
    }
}
