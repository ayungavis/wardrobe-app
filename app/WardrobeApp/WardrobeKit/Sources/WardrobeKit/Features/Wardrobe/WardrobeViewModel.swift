import CoreGraphics
import Foundation
import Observation

@MainActor
@Observable
public final class WardrobeViewModel {
    public private(set) var items: [ClothingItem] = []
    public private(set) var isScanning = false
    /// 0...1, drives the button's label while a batch is running.
    public private(set) var scanProgress: Double = 0

    private var processedPhotoIDs: Set<String> = []
    private let segmentation: GarmentSegmentationService
    private let thumbnails: GarmentThumbnailRepository

    public init(segmentation: GarmentSegmentationService, thumbnails: GarmentThumbnailRepository) {
        self.segmentation = segmentation
        self.thumbnails = thumbnails
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
                items.append(makeItem(category: category, cutout: cutout))
            }
            processedPhotoIDs.insert(photo.id)
        } catch {
            Log.report(error)
        }
    }

    private func makeItem(category: GarmentCategory, cutout: CGImage) -> ClothingItem {
        let id = UUID()
        let path = (try? thumbnails.save(cutout, id: id)) ?? ""
        return ClothingItem(id: id, category: category, dateWorn: Date(), thumbnailPath: path)
    }
}
