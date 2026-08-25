import Foundation
import SwiftData

@MainActor
public protocol WardrobeItemRepository: AnyObject {
    func items() throws -> [WardrobeItem]
    func fingerprints() throws -> [ItemFingerprint]
    func wears(for itemID: UUID) throws -> [WearRecord]
    func insert(_ item: WardrobeItem, fingerprint: ItemFingerprint?, wear: WearRecord?) throws
    func recordWear(_ wear: WearRecord?, fingerprint: ItemFingerprint) throws
    func update(_ item: WardrobeItem) throws
    func delete(itemID: UUID) throws
    func deleteAll() throws
}

// MARK: - SwiftData

@MainActor
public final class SwiftDataWardrobeItemRepository: WardrobeItemRepository {
    private let context: ModelContext
    private let outbox: (any OutboxRepository)?

    public init(context: ModelContext, outbox: (any OutboxRepository)? = nil) {
        self.context = context
        self.outbox = outbox
    }

    public static var schema: Schema {
        Schema([
            WardrobeItemEntity.self, ItemFingerprintEntity.self, WearRecordEntity.self,
            OutboxEntryEntity.self, SyncCursorEntity.self, DiagnosticEntryEntity.self,
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
        return try context.fetch(descriptor).map(\.domain)
    }

    public func insert(_ item: WardrobeItem, fingerprint: ItemFingerprint?, wear: WearRecord?) throws {
        context.insert(WardrobeItemEntity(item))
        if let fingerprint {
            context.insert(ItemFingerprintEntity(fingerprint))
        }
        if let wear {
            context.insert(WearRecordEntity(wear))
        }
        try context.save()
    }

    public func recordWear(_ wear: WearRecord?, fingerprint: ItemFingerprint) throws {
        if let wear {
            context.insert(WearRecordEntity(wear))
        }
        context.insert(ItemFingerprintEntity(fingerprint))
        try context.save()
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

    private func stage(_ mutation: SyncMutation) throws {
        guard let outbox else { return }
        try outbox.stage(mutation.queued(), at: Date())
    }

    private func buriedIdentifiers() throws -> Set<UUID> {
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
