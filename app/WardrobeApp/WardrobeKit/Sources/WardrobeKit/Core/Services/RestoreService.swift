import Foundation

// ponytail: the applier speaks in DTOs because nothing maps the twelve kinds to
// domain types yet — T45 owns that and will know which ones it needs. It must
// write through the store's own ModelContext and never save; the cursor's save
// is what makes the page and its position land together.
@MainActor
protocol RestoreService: AnyObject {
    func apply(_ changes: [ChangeDTO]) throws
}

// ponytail: T38 reads the feed and moves the cursor; nothing applies yet. T45
// replaces this with the real restore, which is the ticket that knows which
// kinds it needs and what a conflict with a local edit means.
@MainActor
final class NoopRestoreService: RestoreService {
    func apply(_: [ChangeDTO]) throws {}
}

@MainActor
final class LocalRestoreService: RestoreService {
    private let wardrobe: SwiftDataWardrobeItemRepository
    private let completions: any CompletedChallengeRepository
    private let preferences: any AccountPreferencesRepository

    init(
        wardrobe: SwiftDataWardrobeItemRepository,
        completions: any CompletedChallengeRepository,
        preferences: any AccountPreferencesRepository
    ) {
        self.wardrobe = wardrobe
        self.completions = completions
        self.preferences = preferences
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
            return applyStatus(record) ? nil : "completion-pending-media"
        case let .wardrobeItemConflict(record):
            return try applyConflict(record) ? nil : "conflict-field"
        case .canvasDocument, .photo, .photoDerivative, .itemCutout, .itemIllustration:
            return "media-backed"
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
                cutoutFile: "",
                createdAt: Date(),
                updatedAt: Date()
            ),
            deletedAt: record.deletedAt,
            revisions: Self.revisions(from: record.attributeRevisions)
        ))
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

    private func applyStatus(_ record: ChallengeCompletionRecordDTO) -> Bool {
        guard let status = CompletionStatus(rawValue: record.status) else { return false }
        return completions.stageStatus(id: record.id, status: status)
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
