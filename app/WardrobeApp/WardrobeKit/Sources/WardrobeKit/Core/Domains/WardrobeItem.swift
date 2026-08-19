import Foundation

/// One garment the user owns. The id is generated on device and is the
/// idempotency key the backend upserts on (docs/wardrobe-generation.md §4).
public struct WardrobeItem: Identifiable, Equatable, Sendable {
    public let id: UUID
    /// User-confirmed, never AI-final (FR-029).
    public var name: String
    public var description: String
    public var category: GarmentCategory
    public var status: ItemStatus
    /// File name of the normalized cut-out: the placeholder shown until an
    /// illustration exists, and the source for re-rendering and recomputing
    /// fingerprints. A **name**, not a path — container paths go stale.
    public var cutoutFile: String
    public var illustrationURL: URL?
    public var styleVersion: String?
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String? = nil,
        description: String = "",
        category: GarmentCategory,
        status: ItemStatus = .pending,
        cutoutFile: String,
        illustrationURL: URL? = nil,
        styleVersion: String? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.name = name ?? category.defaultName
        self.description = description
        self.category = category
        self.status = status
        self.cutoutFile = cutoutFile
        self.illustrationURL = illustrationURL
        self.styleVersion = styleVersion
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Where the item sits in the illustration pipeline. Only `ready` has an
/// illustration; every other state renders the cut-out, so the grid is never
/// blank.
public enum ItemStatus: String, CaseIterable, Codable, Sendable {
    case pending
    case processing
    case ready
    case failed
}
