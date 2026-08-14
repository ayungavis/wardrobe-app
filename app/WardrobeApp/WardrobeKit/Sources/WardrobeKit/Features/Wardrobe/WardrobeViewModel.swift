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
            items = try repository.items()
        } catch {
            Log.report(error)
        }
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
    /// is task A6, and FR-029 requires the user to confirm a merge anyway.
    private func store(category: GarmentCategory, cutout: CGImage) throws {
        let now = Date()
        let id = UUID()
        let item = try WardrobeItem(
            id: id,
            category: category,
            cutoutPath: thumbnails.save(cutout, id: id),
            createdAt: now,
            updatedAt: now
        )
        try repository.insert(
            item,
            fingerprint: nil,
            wear: WearRecord(itemID: id, wornAt: now)
        )
        items.insert(item, at: 0)
    }
}
