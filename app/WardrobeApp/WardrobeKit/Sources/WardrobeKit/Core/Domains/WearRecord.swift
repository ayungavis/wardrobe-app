import Foundation

/// One occasion an item was worn. Separate from `WardrobeItem` so the same
/// garment can be worn many times without duplicating the item (FR-029).
public struct WearRecord: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let itemID: UUID
    /// The challenge completion this wear came from. Nil for the bulk-scan
    /// screen, which imports garments outside the daily loop.
    public let completionID: UUID?
    public let wornAt: Date

    public init(
        id: UUID = UUID(),
        itemID: UUID,
        completionID: UUID? = nil,
        wornAt: Date
    ) {
        self.id = id
        self.itemID = itemID
        self.completionID = completionID
        self.wornAt = wornAt
    }
}
