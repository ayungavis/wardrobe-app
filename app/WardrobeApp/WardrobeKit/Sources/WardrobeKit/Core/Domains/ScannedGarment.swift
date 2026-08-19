import Foundation

public struct ScannedGarment: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let description: String
    public let category: GarmentCategory
    public let cutoutFile: String
    public let fingerprint: ItemFingerprint
    public let matches: [ItemMatch]
    public var decision: Decision

    public init(
        id: UUID,
        name: String? = nil,
        description: String = "",
        category: GarmentCategory,
        cutoutFile: String,
        fingerprint: ItemFingerprint,
        matches: [ItemMatch],
        decision: Decision
    ) {
        self.id = id
        self.name = name ?? category.defaultName
        self.description = description
        self.category = category
        self.cutoutFile = cutoutFile
        self.fingerprint = fingerprint
        self.matches = matches
        self.decision = decision
    }

    public enum Decision: Equatable, Sendable {
        case new
        case existing(UUID)
        case discard
    }

    public static func defaultDecision(for matches: [ItemMatch]) -> Decision {
        guard let best = matches.first, best.confidence == .likely else { return .new }
        return .existing(best.itemID)
    }
}
