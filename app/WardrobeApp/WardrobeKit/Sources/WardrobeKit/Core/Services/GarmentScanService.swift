import CoreGraphics
import Foundation

@MainActor
public protocol GarmentScanService {
    func scan(photo: Data) async throws -> [ScannedGarment]
}

@MainActor
public struct WardrobeGarmentScanService: GarmentScanService {
    private let segmentation: GarmentSegmentationService
    private let thumbnails: GarmentThumbnailRepository
    private let repository: WardrobeItemRepository
    private let allowsMatching: Bool

    private nonisolated static let maxPhotoPixel: CGFloat = 2048

    public init(
        segmentation: GarmentSegmentationService,
        thumbnails: GarmentThumbnailRepository,
        repository: WardrobeItemRepository,
        allowsMatching: Bool = true
    ) {
        self.segmentation = segmentation
        self.thumbnails = thumbnails
        self.repository = repository
        self.allowsMatching = allowsMatching
    }

    public func scan(photo: Data) async throws -> [ScannedGarment] {
        let known = (try? repository.fingerprints()) ?? []
        let categories = Dictionary(
            (try? repository.items())?.map { ($0.id, $0.category) } ?? [],
            uniquingKeysWith: { first, _ in first }
        )

        return try await Self.detect(
            photo: photo, known: known, categories: categories,
            segmentation: segmentation, thumbnails: thumbnails,
            allowsMatching: allowsMatching
        )
    }

    @concurrent
    private static func detect(
        photo: Data,
        known: [ItemFingerprint],
        categories: [UUID: GarmentCategory],
        segmentation: any GarmentSegmentationService,
        thumbnails: any GarmentThumbnailRepository,
        allowsMatching: Bool
    ) async throws -> [ScannedGarment] {
        guard let image = ImageDecoding.downsampledImage(from: photo, maxPixel: maxPhotoPixel) else {
            Log.ui.error("Garment scan: undecodable photo")
            return []
        }
        guard let segments = try segmentation.segment(image) else { return [] }

        return try segmentation.cutouts(from: segments).map { category, cutout in
            try garment(
                category: category, cutout: cutout,
                known: known, categories: categories, thumbnails: thumbnails,
                allowsMatching: allowsMatching
            )
        }
    }

    private nonisolated static func garment(
        category: GarmentCategory,
        cutout: GarmentCutout,
        known: [ItemFingerprint],
        categories: [UUID: GarmentCategory],
        thumbnails: any GarmentThumbnailRepository,
        allowsMatching: Bool
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
        logCalibration(for: fingerprint, category: category, among: known, categories: categories)

        return try ScannedGarment(
            id: id,
            category: category,
            cutoutFile: thumbnails.save(cutout.image, id: id),
            fingerprint: fingerprint,
            matches: allowsMatching ? matches : [],
            decision: ScannedGarment.defaultDecision(for: matches, allowsMatching: allowsMatching)
        )
    }

    private nonisolated static func logCalibration(
        for fingerprint: ItemFingerprint,
        category: GarmentCategory,
        among known: [ItemFingerprint],
        categories: [UUID: GarmentCategory]
    ) {
        guard DevMode.isEnabled else { return }

        let comparable = known.filter {
            $0.version == fingerprint.version && categories[$0.itemID] == category
        }
        let scored = comparable
            .map { (other: $0, comparison: ItemMatching.compare(fingerprint, $0)) }
            .sorted { $0.comparison.score > $1.comparison.score }
            .prefix(Self.calibrationSampleSize)

        for entry in scored {
            let printed = entry.comparison.printDistance.map { String(format: "%.3f", $0) } ?? "none"
            Log.ui.info("""
            Calib garment=\(fingerprint.itemID.uuidString.prefix(8), privacy: .public) \
            cat=\(category.rawValue, privacy: .public) \
            vs=\(entry.other.itemID.uuidString.prefix(8), privacy: .public) \
            dE=\(String(format: "%.1f", entry.comparison.colorDelta), privacy: .public) \
            fp=\(printed, privacy: .public) \
            dAsp=\(String(format: "%.3f", entry.comparison.aspectDelta), privacy: .public) \
            q=\(String(format: "%.2f", entry.comparison.maskQuality), privacy: .public) \
            score=\(String(format: "%.3f", entry.comparison.score), privacy: .public)
            """)
        }
    }

    private nonisolated static let calibrationSampleSize = 5
}
