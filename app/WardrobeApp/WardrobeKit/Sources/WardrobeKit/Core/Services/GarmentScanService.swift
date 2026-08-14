import CoreGraphics
import Foundation

/// Turns one photo into the garments it contains, each already fingerprinted and
/// matched against the wardrobe — the pipeline described in
/// docs/wardrobe-generation.md §3, steps 1–4.
///
/// A protocol because both the bulk-scan screen and the challenge editor drive
/// it, and both need to fake it in tests. Copying this chain into two view
/// models is the surest way to make them disagree.
@MainActor
public protocol GarmentScanService {
    /// Cut-outs are already written to disk; the caller decides which ones
    /// survive confirmation and deletes the rest (FR-029).
    func scan(photo: Data) throws -> [ScannedGarment]
}

@MainActor
public struct WardrobeGarmentScanService: GarmentScanService {
    private let segmentation: GarmentSegmentationService
    private let thumbnails: GarmentThumbnailRepository
    private let repository: WardrobeItemRepository

    /// Photos are decoded to at most this edge before segmentation.
    private static let maxPhotoPixel: CGFloat = 2048

    public init(
        segmentation: GarmentSegmentationService,
        thumbnails: GarmentThumbnailRepository,
        repository: WardrobeItemRepository
    ) {
        self.segmentation = segmentation
        self.thumbnails = thumbnails
        self.repository = repository
    }

    public func scan(photo: Data) throws -> [ScannedGarment] {
        guard let image = ImageDecoding.downsampledImage(from: photo, maxPixel: Self.maxPhotoPixel) else {
            Log.ui.error("Garment scan: undecodable photo")
            return []
        }
        guard let segments = try segmentation.segment(image) else { return [] }

        // Read once per photo: the whole index is small, and threading it
        // through the call chain leaked the caller's batching into every layer.
        let known = (try? repository.fingerprints()) ?? []
        let categories = Dictionary(
            (try? repository.items())?.map { ($0.id, $0.category) } ?? [],
            uniquingKeysWith: { first, _ in first }
        )

        return try segmentation.cutouts(from: segments).map { category, cutout in
            try garment(category: category, cutout: cutout, known: known, categories: categories)
        }
    }

    private func garment(
        category: GarmentCategory,
        cutout: GarmentCutout,
        known: [ItemFingerprint],
        categories: [UUID: GarmentCategory]
    ) throws -> ScannedGarment {
        let id = UUID()
        let fingerprint = ItemFingerprint(
            itemID: id,
            version: GarmentFingerprinting.version,
            colorLab: GarmentFingerprinting.colorSignature(of: cutout.image),
            aspectRatio: GarmentFingerprinting.aspectRatio(of: cutout.image),
            featurePrint: GarmentFingerprinting.featurePrint(of: cutout.image),
            maskQuality: cutout.maskQuality,
            createdAt: Date()
        )
        let matches = ItemMatching.candidates(
            for: fingerprint, category: category, among: known, categories: categories
        )
        Log.ui.info("Match: \(matches.count) candidates, best \(matches.first?.score ?? 0)")

        return try ScannedGarment(
            id: id,
            category: category,
            cutoutFile: thumbnails.save(cutout.image, id: id),
            fingerprint: fingerprint,
            matches: matches,
            decision: ScannedGarment.defaultDecision(for: matches)
        )
    }
}
