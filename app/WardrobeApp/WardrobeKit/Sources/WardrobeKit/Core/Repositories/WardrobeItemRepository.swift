import Foundation
import SwiftData

@MainActor
public protocol WardrobeItemRepository: AnyObject {
    /// Newest first.
    func items() throws -> [WardrobeItem]
    /// The whole matching index — small enough to hold in memory.
    func fingerprints() throws -> [ItemFingerprint]
    func wears(for itemID: UUID) throws -> [WearRecord]
    /// One transaction: the item, its first fingerprint, and the wear that
    /// created it. `fingerprint` is nil until fingerprinting lands (task A5).
    func insert(_ item: WardrobeItem, fingerprint: ItemFingerprint?, wear: WearRecord) throws
    /// An item the user already owns, worn again. The fingerprint is kept too —
    /// one per confirmed wear is what makes later matching stronger (§4).
    func recordWear(_ wear: WearRecord, fingerprint: ItemFingerprint) throws
    /// Updates the user-editable text fields of a wardrobe item.
    func update(_ item: WardrobeItem) throws
    /// One item and everything derived from it — its fingerprints and its wear
    /// records — in one transaction. The cut-out file is the caller's to remove.
    func delete(itemID: UUID) throws
    /// Empties all three tables. Dev-menu reset; the thumbnail files are the
    /// caller's to clean up.
    func deleteAll() throws
}

// MARK: - SwiftData

@MainActor
public final class SwiftDataWardrobeItemRepository: WardrobeItemRepository {
    private let context: ModelContext
    
    public init(container: ModelContainer) {
        context = ModelContext(container)
    }
    
    /// The schema this repository owns. `AppContainer` builds the shared
    /// container from it; tests build an in-memory one.
    public static var schema: Schema {
        Schema([WardrobeItemEntity.self, ItemFingerprintEntity.self, WearRecordEntity.self])
    }
    
    public func items() throws -> [WardrobeItem] {
        let descriptor = FetchDescriptor<WardrobeItemEntity>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try context.fetch(descriptor).map(\.domain)
    }
    
    public func fingerprints() throws -> [ItemFingerprint] {
        try context.fetch(FetchDescriptor<ItemFingerprintEntity>()).map(\.domain)
    }
    
    public func wears(for itemID: UUID) throws -> [WearRecord] {
        let descriptor = FetchDescriptor<WearRecordEntity>(
            predicate: #Predicate { $0.itemID == itemID },
            sortBy: [SortDescriptor(\.wornAt, order: .reverse)]
        )
        return try context.fetch(descriptor).map(\.domain)
    }
    
    public func insert(_ item: WardrobeItem, fingerprint: ItemFingerprint?, wear: WearRecord) throws {
        context.insert(WardrobeItemEntity(item))
        if let fingerprint {
            context.insert(ItemFingerprintEntity(fingerprint))
        }
        context.insert(WearRecordEntity(wear))
        try context.save()
    }
    
    public func recordWear(_ wear: WearRecord, fingerprint: ItemFingerprint) throws {
        context.insert(WearRecordEntity(wear))
        context.insert(ItemFingerprintEntity(fingerprint))
        try context.save()
    }
    
    public func update(_ item: WardrobeItem) throws {
        let itemID = item.id
        let descriptor = FetchDescriptor<WardrobeItemEntity>(predicate: #Predicate { $0.id == itemID })
        guard let entity = try context.fetch(descriptor).first else {
            throw AppError.unexpected // item doesn't exist — nothing to update
        }
        entity.name = item.name
        entity.itemDescription = item.description
        entity.updatedAt = item.updatedAt
        try context.save()
    }
    
    public func delete(itemID: UUID) throws {
        // One save for all three, so a failure leaves the item whole rather than
        // stripped of the wear history that gives it meaning.
        try context.delete(model: WardrobeItemEntity.self, where: #Predicate { $0.id == itemID })
        try context.delete(model: ItemFingerprintEntity.self, where: #Predicate { $0.itemID == itemID })
        try context.delete(model: WearRecordEntity.self, where: #Predicate { $0.itemID == itemID })
        try context.save()
    }
    
    public func deleteAll() throws {
        try context.delete(model: WardrobeItemEntity.self)
        try context.delete(model: ItemFingerprintEntity.self)
        try context.delete(model: WearRecordEntity.self)
        try context.save()
    }
}

// MARK: - Storage entities

//
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
    /// Column keeps its old name so no schema migration is needed; the domain
    /// calls it `cutoutFile` because that is what it now holds.
    var cutoutPath: String = ""
    var illustrationURL: URL?
    var styleVersion: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    
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
