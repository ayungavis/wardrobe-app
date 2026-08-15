import Foundation

/// A wardrobe item that might be the garment just scanned.
///
/// Never acted on automatically: FR-029 says the AI proposes and the user
/// decides, so this only ever feeds a confirmation UI.
public struct ItemMatch: Identifiable, Equatable, Sendable {
    public var id: UUID {
        itemID
    }

    public let itemID: UUID
    /// 0...1, higher is more alike.
    public let score: Float
    public let confidence: Confidence

    public init(itemID: UUID, score: Float, confidence: Confidence) {
        self.itemID = itemID
        self.score = score
        self.confidence = confidence
    }

    public enum Confidence: Sendable, Equatable {
        /// Proposed with the option pre-selected.
        case likely
        /// Proposed, but the user has to reach for it.
        case uncertain
    }
}
