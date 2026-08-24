import Foundation
import Observation

@MainActor
@Observable
public final class GarmentReviewModel {
    public private(set) var garments: [ScannedGarment] = []
    public private(set) var isScanning = false

    private var scannedPhotoID: UUID?
    private let scanner: GarmentScanService
    private let photoRepository: PhotoRepository
    private let wardrobeRepository: WardrobeItemRepository
    private let thumbnails: GarmentThumbnailRepository
    private(set) var scanTask: Task<Void, Never>?

    public init(
        scanner: GarmentScanService,
        photoRepository: PhotoRepository,
        wardrobeRepository: WardrobeItemRepository,
        thumbnails: GarmentThumbnailRepository
    ) {
        self.scanner = scanner
        self.photoRepository = photoRepository
        self.wardrobeRepository = wardrobeRepository
        self.thumbnails = thumbnails
    }

    // ponytail: segmentation runs on the main actor, same as the bulk-scan
    // screen — a second of jank on a big photo. Moving Core ML off the main
    // actor is the upgrade when it starts to bite.

    public func scanIfNeeded(photoID: UUID?) {
        guard let photoID, scannedPhotoID != photoID else { return }
        scannedPhotoID = photoID
        scan { [photoRepository] in try photoRepository.loadOriginal(id: photoID) }
    }

    public func scan(photo: Data) {
        scan(wornAt: CaptureDate.original(in: photo)) { photo }
    }

    private func scan(wornAt: Date? = nil, _ load: @escaping () throws -> Data) {
        let previous = scanTask
        isScanning = true

        scanTask = Task {
            await previous?.value
            defer { isScanning = false }
            do {
                let photo = try load()
                guard !Task.isCancelled else { return }
                let start = ContinuousClock.now
                try await stage(scanner.scan(photo: photo).map { garment in
                    var dated = garment
                    dated.wornAt = wornAt
                    return dated
                })
                Log.ui.info(
                    "Garment scan finished in \((ContinuousClock.now - start).ms, privacy: .public)ms"
                )
            } catch {
                Log.report(error)
            }
        }
    }

    public func cancel() {
        scanTask?.cancel()
        for garment in garments {
            try? thumbnails.delete(file: garment.cutoutFile)
        }
        garments = []
        scannedPhotoID = nil
    }

    public func finishScanning() async {
        await scanTask?.value
    }

    func stage(_ garments: [ScannedGarment]) {
        self.garments.append(contentsOf: garments)
    }

    public func choose(_ decision: ScannedGarment.Decision, for garmentID: UUID) {
        guard let index = garments.firstIndex(where: { $0.id == garmentID }) else { return }
        garments[index].decision = decision
    }

    public func thumbnailData(forFile file: String) -> Data? {
        try? thumbnails.data(forFile: file)
    }

    public func thumbnailData(forItemID itemID: UUID) -> Data? {
        guard let item = try? wardrobeRepository.items().first(where: { $0.id == itemID }) else {
            return nil
        }
        return thumbnailData(forFile: item.cutoutFile)
    }

    public func commit(completionID: UUID?, at date: Date) {
        for garment in garments {
            record(garment, wornAt: completionID.map { _ in date }, completionID: completionID, at: date)
        }
        garments = []
    }

    public func commitImported() {
        var undated: [ScannedGarment] = []
        for garment in garments {
            if garment.decision == .discard {
                record(garment, wornAt: nil, completionID: nil, at: .now)
                continue
            }
            guard let wornAt = garment.wornAt else {
                undated.append(garment)
                continue
            }
            record(garment, wornAt: wornAt, completionID: nil, at: wornAt)
        }
        garments = undated
    }

    public func setWornAt(_ date: Date, for garmentID: UUID) {
        guard let index = garments.firstIndex(where: { $0.id == garmentID }) else { return }
        garments[index].wornAt = date
    }

    public var isMissingAWearDate: Bool {
        garments.contains { $0.wornAt == nil && $0.decision != .discard }
    }

    private func record(
        _ garment: ScannedGarment,
        wornAt: Date?,
        completionID: UUID?,
        at date: Date
    ) {
        do {
            switch garment.decision {
            case .new:
                try insert(garment, wornAt: wornAt, completionID: completionID, at: date)
            case let .existing(itemID):
                try merge(garment, into: itemID, wornAt: wornAt, completionID: completionID, at: date)
            case .discard:
                try thumbnails.delete(file: garment.cutoutFile)
            }
        } catch {
            Log.report(error)
        }
    }

    private func insert(
        _ garment: ScannedGarment,
        wornAt: Date?,
        completionID: UUID?,
        at date: Date
    ) throws {
        let wear = wornAt.map { WearRecord(itemID: garment.id, completionID: completionID, wornAt: $0) }
        try wardrobeRepository.insert(
            WardrobeItem(
                id: garment.id,
                name: garment.name,
                description: garment.description,
                category: garment.category,
                cutoutFile: garment.cutoutFile,
                createdAt: date,
                updatedAt: date
            ),
            fingerprint: garment.fingerprint,
            wear: wear
        )
    }

    private func merge(
        _ garment: ScannedGarment,
        into itemID: UUID,
        wornAt: Date?,
        completionID: UUID?,
        at date: Date
    ) throws {
        let wear = wornAt.map { WearRecord(itemID: itemID, completionID: completionID, wornAt: $0) }
        try wardrobeRepository.recordWear(
            wear,
            fingerprint: ItemFingerprint(
                itemID: itemID,
                version: garment.fingerprint.version,
                colorLab: garment.fingerprint.colorLab,
                aspectRatio: garment.fingerprint.aspectRatio,
                featurePrint: garment.fingerprint.featurePrint,
                maskQuality: garment.fingerprint.maskQuality,
                createdAt: date
            )
        )
        try thumbnails.delete(file: garment.cutoutFile)
    }

    public func wardrobeItems(in category: GarmentCategory) -> [WardrobeItem] {
        (try? wardrobeRepository.items().filter { $0.category == category }) ?? []
    }

    public var activeGarments: [ScannedGarment] {
        garments.filter { $0.decision != .discard }
    }
}
