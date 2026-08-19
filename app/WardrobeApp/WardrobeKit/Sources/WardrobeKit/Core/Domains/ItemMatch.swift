import Foundation

public struct ItemMatch: Identifiable, Equatable, Sendable {
    public var id: UUID {
        itemID
    }

    public let itemID: UUID
    public let score: Float
    public let confidence: Confidence

    public init(itemID: UUID, score: Float, confidence: Confidence) {
        self.itemID = itemID
        self.score = score
        self.confidence = confidence
    }

    public enum Confidence: Sendable, Equatable {
        case likely
        case uncertain
    }
}
