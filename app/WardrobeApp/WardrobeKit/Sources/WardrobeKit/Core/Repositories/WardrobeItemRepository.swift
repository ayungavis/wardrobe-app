import Foundation
import SwiftData

@MainActor
public protocol WardrobeItemRepository: AnyObject {
    func items() throws -> [WardrobeItem]
    func fingerprints() throws -> [ItemFingerprint]
    func wears(for itemID: UUID) throws -> [WearRecord]
    func openConflicts() throws -> [ItemConflict]
    func resolveConflict(_ conflict: ItemConflict, choosing choice: ConflictChoice) throws
    func merge(winnerID: UUID, loserID: UUID) throws
    func insert(_ item: WardrobeItem, fingerprint: ItemFingerprint?, wear: WearRecord?) throws
    func stageInsert(_ item: WardrobeItem, fingerprint: ItemFingerprint?, wear: WearRecord?)
    func recordWear(_ wear: WearRecord?, fingerprint: ItemFingerprint) throws
    func stageWear(_ wear: WearRecord?, fingerprint: ItemFingerprint)
    func commitStaged() throws
    func discardStaged()
    func update(_ item: WardrobeItem) throws
    func delete(itemID: UUID) throws
    func deleteAll() throws
}

// MARK: - SwiftData

@MainActor
public final class SwiftDataWardrobeItemRepository: WardrobeItemRepository {
    let context: ModelContext
    private let outbox: (any OutboxRepository)?

    public init(context: ModelContext, outbox: (any OutboxRepository)? = nil) {
        self.context = context
        self.outbox = outbox
    }

    public static var schema: Schema {
        Schema([
            WardrobeItemEntity.self, ItemFingerprintEntity.self, WearRecordEntity.self,
            OutboxEntryEntity.self, SyncCursorEntity.self, DiagnosticEntryEntity.self,
            CompletionEntity.self, MediaUploadEntity.self, ItemConflictEntity.self,
            MediaDownloadEntity.self,
        ])
    }

    public func items() throws -> [WardrobeItem] {
        let descriptor = FetchDescriptor<WardrobeItemEntity>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try context.fetch(descriptor).map(\.domain)
    }

    // ponytail: filtered in Swift rather than by predicate because SwiftData
    // cannot join a fingerprint to its item; the set is one row per item and the
    // matcher already loads every fingerprint anyway.
    public func fingerprints() throws -> [ItemFingerprint] {
        let buried = try buriedIdentifiers()
        return try context.fetch(FetchDescriptor<ItemFingerprintEntity>())
            .filter { !buried.contains($0.itemID) }
            .map(\.domain)
    }

    public func wears(for itemID: UUID) throws -> [WearRecord] {
        let descriptor = FetchDescriptor<WearRecordEntity>(
            predicate: #Predicate { $0.itemID == itemID },
            sortBy: [SortDescriptor(\.wornAt, order: .reverse)]
        )
        let excluded = try nonCanonicalCompletionIDs()
        return try context.fetch(descriptor)
            .filter { wear in wear.completionID.map { !excluded.contains($0) } ?? true }
            .map(\.domain)
    }

    private func nonCanonicalCompletionIDs() throws -> Set<UUID> {
        let canonical = CompletionStatus.canonical.rawValue
        let descriptor = FetchDescriptor<CompletionEntity>(
            predicate: #Predicate { $0.status != canonical }
        )
        return try Set(
            context.fetch(descriptor)
                .filter { $0.domain?.isDeliberateExtra != true }
                .map(\.id)
        )
    }

    public func insert(_ item: WardrobeItem, fingerprint: ItemFingerprint?, wear: WearRecord?) throws {
        stageInsert(item, fingerprint: fingerprint, wear: wear)
        try context.save()
    }

    public func stageInsert(_ item: WardrobeItem, fingerprint: ItemFingerprint?, wear: WearRecord?) {
        context.insert(WardrobeItemEntity(item))
        if let fingerprint {
            context.insert(ItemFingerprintEntity(fingerprint))
        }
        if let wear {
            context.insert(WearRecordEntity(wear))
        }
    }

    public func recordWear(_ wear: WearRecord?, fingerprint: ItemFingerprint) throws {
        stageWear(wear, fingerprint: fingerprint)
        try context.save()
    }

    public func stageWear(_ wear: WearRecord?, fingerprint: ItemFingerprint) {
        if let wear {
            context.insert(WearRecordEntity(wear))
        }
        context.insert(ItemFingerprintEntity(fingerprint))
    }

    public struct PulledItem {
        public let item: WardrobeItem
        public let deletedAt: Date?
        public let revisions: PulledRevisions

        public init(item: WardrobeItem, deletedAt: Date?, revisions: PulledRevisions) {
            self.item = item
            self.deletedAt = deletedAt
            self.revisions = revisions
        }
    }

    public struct PulledRevisions {
        public let category: Int64
        public let name: Int64
        public let description: Int64

        public init(category: Int64, name: Int64, description: Int64) {
            self.category = category
            self.name = name
            self.description = description
        }
    }

    // ponytail: the local cutout path survives a pulled edit — the feed knows
    // nothing about this device's files, and blanking it would orphan the image.
    func stageApply(_ pulled: PulledItem) throws {
        let itemID = pulled.item.id
        let descriptor = FetchDescriptor<WardrobeItemEntity>(predicate: #Predicate { $0.id == itemID })
        let entity: WardrobeItemEntity
        if let existing = try context.fetch(descriptor).first {
            entity = existing
        } else {
            entity = WardrobeItemEntity(pulled.item)
            context.insert(entity)
        }
        entity.name = pulled.item.name
        entity.itemDescription = pulled.item.description
        entity.category = pulled.item.category.rawValue
        entity.currentIllustrationID = pulled.item.currentIllustrationID
        entity.deletedAt = pulled.deletedAt
        entity.categoryRev = pulled.revisions.category
        entity.nameRev = pulled.revisions.name
        entity.descriptionRev = pulled.revisions.description
        entity.updatedAt = Date()
    }

    func stageApply(fingerprint: ItemFingerprint) throws {
        let fingerprintID = fingerprint.id
        let descriptor = FetchDescriptor<ItemFingerprintEntity>(
            predicate: #Predicate { $0.id == fingerprintID }
        )
        if let existing = try context.fetch(descriptor).first {
            existing.itemID = fingerprint.itemID
            return
        }
        context.insert(ItemFingerprintEntity(fingerprint))
    }

    func stageInsert(fingerprint: ItemFingerprint) {
        context.insert(ItemFingerprintEntity(fingerprint))
    }

    func stageCutout(itemID: UUID, path: String) {
        fetchItem(itemID)?.cutoutPath = path
    }

    private func fetchItem(_ itemID: UUID) -> WardrobeItemEntity? {
        do {
            return try context.fetch(
                FetchDescriptor<WardrobeItemEntity>(predicate: #Predicate { $0.id == itemID })
            ).first
        } catch {
            Log.report(error, context: Log.Context(operation: "wardrobe.fetchItem"))
            return nil
        }
    }

    func stageInsert(wear: WearRecord) {
        context.insert(WearRecordEntity(wear))
    }

    func stageApply(wear: WearRecord, deletedAt: Date?) throws {
        let wearID = wear.id
        let existing = try context.fetch(
            FetchDescriptor<WearRecordEntity>(predicate: #Predicate { $0.id == wearID })
        ).first
        if deletedAt != nil {
            if let existing {
                context.delete(existing)
            }
            return
        }
        context.insert(WearRecordEntity(wear))
    }

    public func commitStaged() throws {
        try context.save()
    }

    public func discardStaged() {
        context.rollback()
    }

    public func update(_ item: WardrobeItem) throws {
        let itemID = item.id
        let descriptor = FetchDescriptor<WardrobeItemEntity>(predicate: #Predicate { $0.id == itemID })
        guard let entity = try context.fetch(descriptor).first, entity.deletedAt == nil else {
            throw AppError.unexpected
        }

        var args = UpsertItemArgsDTO(id: itemID)
        if entity.category != item.category.rawValue {
            entity.category = item.category.rawValue
            entity.categoryRev += 1
            args.category = ItemFieldDTO(value: item.category.rawValue, rev: entity.categoryRev)
        }
        if entity.name != item.name {
            entity.name = item.name
            entity.nameRev += 1
            args.name = ItemFieldDTO(value: item.name, rev: entity.nameRev)
        }
        if entity.itemDescription != item.description {
            entity.itemDescription = item.description
            entity.descriptionRev += 1
            args.description = ItemFieldDTO(value: item.description, rev: entity.descriptionRev)
        }

        guard args.category != nil || args.name != nil || args.description != nil else { return }
        entity.updatedAt = item.updatedAt
        try stage(.upsertItem(args))
        try context.save()
    }

    // ponytail: fingerprints and wears deliberately survive the tombstone. The
    // server reconciles fingerprints by set union as immutable versions (FR-063),
    // so erasing them locally would contradict the record it keeps.
    public func delete(itemID: UUID) throws {
        let descriptor = FetchDescriptor<WardrobeItemEntity>(predicate: #Predicate { $0.id == itemID })
        guard let entity = try context.fetch(descriptor).first, entity.deletedAt == nil else {
            return
        }
        entity.deletedAt = Date()
        try stage(.deleteItem(DeleteItemArgsDTO(id: itemID)))
        try context.save()
    }

    func stage(_ mutation: SyncMutation) throws {
        guard let outbox else { return }
        try outbox.stage(mutation.queued(), at: Date())
    }

    func buriedIdentifiers() throws -> Set<UUID> {
        let descriptor = FetchDescriptor<WardrobeItemEntity>(predicate: #Predicate { $0.deletedAt != nil })
        return try Set(context.fetch(descriptor).map(\.id))
    }

    public func deleteAll() throws {
        try context.delete(model: WardrobeItemEntity.self)
        try context.delete(model: ItemFingerprintEntity.self)
        try context.delete(model: WearRecordEntity.self)
        try context.save()
    }
}

// MARK: - Storage entities

// ponytail: plain `itemID` columns instead of SwiftData relationships — it
// mirrors the Postgres schema in docs/wardrobe-generation.md, needs no cascade
// configuration, and matching loads every fingerprint anyway.

@Model
final class WardrobeItemEntity {
    #Unique<WardrobeItemEntity>([\.id])
    private(set) var id: UUID = UUID()
    var name: String = ""
    var itemDescription: String = ""
    var category: String = GarmentCategory.top.rawValue
    var status: String = ItemStatus.pending.rawValue
    var cutoutPath: String = ""
    var illustrationURL: URL?
    var styleVersion: String?
    var currentIllustrationID: UUID?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?
    var categoryRev: Int64 = 0
    var nameRev: Int64 = 0
    var descriptionRev: Int64 = 0

    init(_ item: WardrobeItem) {
        id = item.id
        name = item.name
        itemDescription = item.description
        category = item.category.rawValue
        status = item.status.rawValue
        cutoutPath = item.cutoutFile
        illustrationURL = item.illustrationURL
        styleVersion = item.styleVersion
        currentIllustrationID = item.currentIllustrationID
        createdAt = item.createdAt
        updatedAt = item.updatedAt
    }

    var domain: WardrobeItem {
        WardrobeItem(
            id: id,
            name: name,
            description: itemDescription,
            category: GarmentCategory(rawValue: category) ?? .top,
            status: ItemStatus(rawValue: status) ?? .pending,
            cutoutFile: cutoutPath,
            illustrationURL: illustrationURL,
            styleVersion: styleVersion,
            currentIllustrationID: currentIllustrationID,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

@Model
final class ItemFingerprintEntity {
    #Unique<ItemFingerprintEntity>([\.id])
    private(set) var id: UUID = UUID()
    var itemID: UUID = UUID()
    var version: String = ""
    var colorLab: [Float] = []
    var aspectRatio: Float = 0
    @Attribute(.externalStorage) var featurePrint: Data = Data()
    var maskQuality: Float = 0
    var createdAt: Date = Date()

    init(_ fingerprint: ItemFingerprint) {
        id = fingerprint.id
        itemID = fingerprint.itemID
        version = fingerprint.version
        colorLab = fingerprint.colorLab
        aspectRatio = fingerprint.aspectRatio
        featurePrint = fingerprint.featurePrint
        maskQuality = fingerprint.maskQuality
        createdAt = fingerprint.createdAt
    }

    var domain: ItemFingerprint {
        ItemFingerprint(
            id: id,
            itemID: itemID,
            version: version,
            colorLab: colorLab,
            aspectRatio: aspectRatio,
            featurePrint: featurePrint,
            maskQuality: maskQuality,
            createdAt: createdAt
        )
    }
}

@Model
final class WearRecordEntity {
    #Unique<WearRecordEntity>([\.id])
    private(set) var id: UUID = UUID()
    var itemID: UUID = UUID()
    var completionID: UUID?
    var wornAt: Date = Date()

    init(_ wear: WearRecord) {
        id = wear.id
        itemID = wear.itemID
        completionID = wear.completionID
        wornAt = wear.wornAt
    }

    var domain: WearRecord {
        WearRecord(id: id, itemID: itemID, completionID: completionID, wornAt: wornAt)
    }
}
