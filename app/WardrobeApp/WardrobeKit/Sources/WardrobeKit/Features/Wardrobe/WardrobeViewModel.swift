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

    /// Each entry is a stable identifier plus the photo's bytes. Photos whose
    /// identifier was processed before are skipped.
    public func process(_ photos: [(id: String, data: Data)]) async {
        isScanning = true
        defer { isScanning = false }

        let fresh = photos.filter { !processedPhotoIDs.contains($0.id) }
        Log.ui.info("Wardrobe scan: \(fresh.count) new of \(photos.count) selected")
        guard !fresh.isEmpty else { return }

        for (index, photo) in fresh.enumerated() {
            scanProgress = Double(index) / Double(fresh.count)
            process(photo)
        }
        scanProgress = 1
    }

    private func process(_ photo: (id: String, data: Data)) {
        guard let image = ImageDecoding.downsampledImage(from: photo.data, maxPixel: 2048) else {
            Log.ui.error("Wardrobe scan: undecodable photo")
            return
        }

        do {
            guard let result = try segmentation.segment(image) else { return }
            for (category, cutout) in segmentation.cutouts(from: result) {
                try store(category: category, cutout: cutout)
            }
            processedPhotoIDs.insert(photo.id)
        } catch {
            Log.report(error)
        }
    }

    /// ponytail: every scanned garment becomes a new item — duplicate matching
    /// is task A6, and FR-029 requires the user to confirm a merge anyway. The
    /// fingerprint is already recorded so that matching has history to work with
    /// the moment it lands.
    private func store(category: GarmentCategory, cutout: GarmentCutout) throws {
        let now = Date()
        let id = UUID()
        let item = try WardrobeItem(
            id: id,
            category: category,
            cutoutFile: thumbnails.save(cutout.image, id: id),
            createdAt: now,
            updatedAt: now
        )
        try repository.insert(
            item,
            fingerprint: fingerprint(for: id, cutout: cutout, at: now),
            wear: WearRecord(itemID: id, wornAt: now)
        )
        items.insert(item, at: 0)
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
