import Foundation

// ponytail: the applier speaks in DTOs because nothing maps the twelve kinds to
// domain types yet — T45 owns that and will know which ones it needs. It must
// write through the store's own ModelContext and never save; the cursor's save
// is what makes the page and its position land together.
// The feed is incremental: a record the client has already consumed never
// arrives again. Raise this number in the same commit whenever the applier
// starts reading a field or kind it used to drop — that rewinds every device's
// cursor once so the old records are re-read under the new reading.
enum FeedInterpretation {
    static let version = 2
}

@MainActor
protocol RestoreService: AnyObject {
    func apply(_ changes: [ChangeDTO]) throws
    func restoreDueMedia(at date: Date) async -> (restored: Int, fatal: AppError?)
}

// ponytail: T38 reads the feed and moves the cursor; nothing applies yet. T45
// replaces this with the real restore, which is the ticket that knows which
// kinds it needs and what a conflict with a local edit means.
@MainActor
final class NoopRestoreService: RestoreService {
    func apply(_: [ChangeDTO]) throws {}

    func restoreDueMedia(at _: Date) async -> (restored: Int, fatal: AppError?) {
        (0, nil)
    }
}

@MainActor
final class LocalRestoreService: RestoreService {
    private let wardrobe: SwiftDataWardrobeItemRepository
    private let completions: SwiftDataCompletedChallengeRepository
    private let preferences: any AccountPreferencesRepository
    private let downloads: any MediaDownloadRepository
    private let media: any MediaRepository
    private let photos: any PhotoRepository
    private let previews: any CompletionPreviewRepository
    private let thumbnails: any GarmentThumbnailRepository

    init(
        wardrobe: SwiftDataWardrobeItemRepository,
        completions: SwiftDataCompletedChallengeRepository,
        preferences: any AccountPreferencesRepository,
        downloads: any MediaDownloadRepository,
        media: any MediaRepository,
        photos: any PhotoRepository,
        previews: any CompletionPreviewRepository,
        thumbnails: any GarmentThumbnailRepository
    ) {
        self.wardrobe = wardrobe
        self.completions = completions
        self.preferences = preferences
        self.downloads = downloads
        self.media = media
        self.photos = photos
        self.previews = previews
        self.thumbnails = thumbnails
    }

    func apply(_ changes: [ChangeDTO]) throws {
        var skipped: [String: Int] = [:]
        for change in changes {
            if let label = try apply(change) {
                skipped[label, default: 0] += 1
            }
        }
        if !skipped.isEmpty {
            Log.network.info("Feed kinds not applied yet: \(skipped.description, privacy: .public)")
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    private func apply(_ change: ChangeDTO) throws -> String? {
        switch change.record {
        case let .wardrobeItem(record):
            try applyItem(record)
        case let .itemFingerprint(record):
            try applyFingerprint(record)
        case let .wearRecord(record):
            try applyWear(record)
        case let .accountPreference(record):
            applyPreference(record)
        case let .challengeCompletion(record):
            return applyCompletion(record)
        case let .wardrobeItemConflict(record):
            return try applyConflict(record) ? nil : "conflict-field"
        case let .canvasDocument(record):
            applyDocument(record)
        case let .photoDerivative(record):
            applyDerivative(record)
        case let .photo(record):
            applyPhoto(record)
        case let .itemCutout(record):
            applyCutout(record)
        case let .itemIllustration(record):
            applyIllustration(record)
        case .activeChallenge:
            return "activeChallenge"
        case let .unrecognised(kind):
            return kind
        }
        return nil
    }

    private func applyItem(_ record: WardrobeItemRecordDTO) throws {
        try wardrobe.stageApply(SwiftDataWardrobeItemRepository.PulledItem(
            item: WardrobeItem(
                id: record.id,
                name: record.name,
                description: record.description ?? "",
                category: GarmentCategory(rawValue: record.category) ?? .top,
                status: Self.status(of: record.illustrationState),
                cutoutFile: "",
                currentIllustrationID: record.currentIllustrationId,
                createdAt: Date(),
                updatedAt: Date()
            ),
            deletedAt: record.deletedAt,
            revisions: Self.revisions(from: record.attributeRevisions)
        ))
    }

    private static func status(of illustrationState: String) -> ItemStatus {
        switch illustrationState {
        case "queued": .pending
        case "rendering": .processing
        case "ready": .ready
        case "failed": .failed
        case "none": .undrawn
        default: .pending
        }
    }

    private static func revisions(from tree: JSONValue) -> SwiftDataWardrobeItemRepository.PulledRevisions {
        func rev(_ field: String) -> Int64 {
            guard case let .object(fields) = tree,
                  case let .object(entry) = fields[field] ?? .null,
                  case let .int(value) = entry["rev"] ?? .null
            else {
                return 0
            }
            return Int64(value)
        }
        return SwiftDataWardrobeItemRepository.PulledRevisions(
            category: rev("category"), name: rev("name"), description: rev("description")
        )
    }

    private func applyFingerprint(_ record: ItemFingerprintRecordDTO) throws {
        try wardrobe.stageApply(fingerprint: ItemFingerprint(
            id: record.id,
            itemID: record.itemId,
            version: record.version,
            colorLab: record.colorLab.map(Float.init),
            aspectRatio: Float(record.aspectRatio),
            featurePrint: record.featurePrint,
            maskQuality: Float(record.maskQuality),
            createdAt: Date()
        ))
    }

    private func applyWear(_ record: WearRecordRecordDTO) throws {
        let wornAt = Self.wornOnFormat.date(from: record.wornOn) ?? Date()
        try wardrobe.stageApply(
            wear: WearRecord(
                id: record.id, itemID: record.itemId,
                completionID: record.completionId, wornAt: wornAt
            ),
            deletedAt: record.deletedAt
        )
    }

    private func applyConflict(_ record: WardrobeItemConflictRecordDTO) throws -> Bool {
        guard let field = ConflictField(rawValue: record.field) else { return false }
        try wardrobe.stageApply(conflict: ItemConflict(
            id: record.id, itemID: record.itemId, field: field,
            value: record.value, revision: record.revision, resolvedAt: record.resolvedAt
        ))
        return true
    }

    private func applyCompletion(_ record: ChallengeCompletionRecordDTO) -> String? {
        guard record.deletedAt == nil else { return "completion-tombstone" }
        guard let status = CompletionStatus(rawValue: record.status) else { return "completion-status" }
        completions.stageRestore(
            RestoredCompletion(
                id: record.id, cardID: record.cardId, status: status,
                completedAt: record.completedAt, photoID: record.photoId,
                derivativeID: record.currentDerivativeId
            ),
            card: Self.card(for: record.cardId)
        )
        return nil
    }

    private static func card(for id: UUID) -> ChallengeCard {
        guard id != ChallengeCard.freestyle.id else { return .freestyle }
        return ChallengeCard(
            id: id,
            prompt: String(localized: "history.restored.prompt", bundle: .module)
        )
    }

    private func applyDocument(_ record: CanvasDocumentRecordDTO) {
        guard record.deletedAt == nil else { return }
        guard record.schemaVersion <= Int32(EditorDocument.currentSchemaVersion) else {
            completions.stageDocumentState(id: record.completionId, .unsupported)
            return
        }
        guard completions.needsDocument(id: record.completionId) else { return }
        downloads.stage(MediaDownload(
            id: record.mediaObjectId,
            destination: .completionDocument(completionID: record.completionId)
        ))
    }

    private func applyDerivative(_ record: PhotoDerivativeRecordDTO) {
        guard record.deletedAt == nil,
              let completionID = completions.completionID(forDerivative: record.id)
        else {
            return
        }
        downloads.stage(MediaDownload(
            id: record.mediaObjectId,
            destination: .completionPreview(completionID: completionID)
        ))
    }

    private func applyPhoto(_ record: PhotoRecordDTO) {
        guard record.deletedAt == nil, !photos.hasOriginal(id: record.id) else { return }
        downloads.stage(MediaDownload(
            id: record.mediaObjectId,
            destination: .photoOriginal(photoID: record.id)
        ))
    }

    private func applyIllustration(_ record: ItemIllustrationRecordDTO) {
        guard record.deletedAt == nil,
              (try? thumbnails.data(forFile: "\(record.id.uuidString).png")) == nil
        else {
            return
        }
        downloads.stage(MediaDownload(
            id: record.mediaObjectId,
            destination: .itemIllustration(illustrationID: record.id)
        ))
    }

    private func applyCutout(_ record: ItemCutoutRecordDTO) {
        guard record.deletedAt == nil else { return }
        downloads.stage(MediaDownload(
            id: record.mediaObjectId,
            destination: .itemCutout(itemID: record.itemId)
        ))
    }

    private static let wornOnFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private func applyPreference(_ record: AccountPreferenceRecordDTO) {
        var stored = preferences.load()
        stored.recentStickerIDs = record.recentStickerIds
        stored.onboardingCompletedAt = record.onboardingCompletedAt ?? stored.onboardingCompletedAt
        stored.uploadConsentAt = record.uploadConsentAt ?? stored.uploadConsentAt
        preferences.applyRemote(stored)
    }
}

// MARK: - The download phase

extension LocalRestoreService {
    func restoreDueMedia(at date: Date) async -> (restored: Int, fatal: AppError?) {
        let due = (try? downloads.due(at: date, limit: SyncBatching.maxMutations)) ?? []
        var restored = 0
        for row in due {
            do {
                let bytes = try await media.data(for: row.id)
                try write(bytes, to: row.destination)
                try downloads.acknowledge(id: row.id)
                restored += 1
            } catch is CancellationError {
                return (restored, nil)
            } catch AppError.sessionExpired {
                return (restored, .sessionExpired)
            } catch AppError.documentFromNewerApp {
                markUnsupported(row)
            } catch {
                let failure = AppError(wrapping: error)
                Log.report(failure, context: Log.Context(operation: "restore.download"), logger: Log.network)
                try? downloads.recordFailure(of: row.id, error: failure, code: nil, at: date)
            }
        }
        return (restored, nil)
    }

    private func write(_ bytes: Data, to destination: MediaDownloadDestination) throws {
        switch destination {
        case let .completionPreview(completionID):
            let file = try previews.save(bytes, id: completionID)
            completions.stagePreview(id: completionID, file: file)
            try completions.commitStaged()
        case let .completionDocument(completionID):
            let document = try JSONDecoder().decode(EditorDocument.self, from: bytes)
            completions.stageDocument(id: completionID, document)
            try completions.commitStaged()
        case let .photoOriginal(photoID):
            try photos.saveOriginal(bytes, id: photoID)
        case let .itemCutout(itemID):
            let file = try thumbnails.save(bytes, id: itemID)
            wardrobe.stageCutout(itemID: itemID, path: file)
            try wardrobe.commitStaged()
        case let .itemIllustration(illustrationID):
            try thumbnails.save(bytes, id: illustrationID)
        }
    }

    private func markUnsupported(_ row: MediaDownload) {
        if case let .completionDocument(completionID) = row.destination {
            completions.stageDocumentState(id: completionID, .unsupported)
            try? completions.commitStaged()
        }
        try? downloads.acknowledge(id: row.id)
    }
}
