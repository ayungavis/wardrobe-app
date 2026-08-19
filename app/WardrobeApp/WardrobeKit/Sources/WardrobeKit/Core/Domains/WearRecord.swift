import Foundation

public struct WearRecord: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let itemID: UUID
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
