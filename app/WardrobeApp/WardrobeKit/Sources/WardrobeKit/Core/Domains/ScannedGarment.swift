import Foundation

/// A garment found in a scan, waiting for the user to say what it is.
///
/// Nothing is written until they confirm: FR-029 forbids merging a duplicate or
/// bumping a wear count without the user's say-so.
public struct ScannedGarment: Identifiable, Equatable, Sendable {
    /// Becomes the item's id if the user keeps it as a new garment.
    public let id: UUID
    public let name: String
    public let description: String
    public let category: GarmentCategory
    /// Already on disk — holding forty 1024² images in memory through a review
    /// would cost hundreds of megabytes, so the orphans are deleted instead.
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
        /// Segmentation was wrong — a bag, a shadow, a slice of background.
        /// Kept out of the wardrobe so it never becomes a match candidate.
        case discard
    }

    /// Pre-selects the proposal only when matching was confident, which is what
    /// `ItemMatch.Confidence` promises.
    public static func defaultDecision(for matches: [ItemMatch]) -> Decision {
        guard let best = matches.first, best.confidence == .likely else { return .new }
        return .existing(best.itemID)
    }
}
