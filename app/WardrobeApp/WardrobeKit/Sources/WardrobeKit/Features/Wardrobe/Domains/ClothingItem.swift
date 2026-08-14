import Foundation

// ponytail: the temporary bulk-scan UI's own model. It merges with the
// `WardrobeItem` designed in docs/wardrobe-generation.md at task A1 — the two
// are deliberately kept apart until then.

/// A garment detected in a photo and cut out of it.
public struct ClothingItem: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let category: GarmentCategory
    public let dominantColor: String?
    public let dateWorn: Date
    public let thumbnailPath: String

    public init(
        id: UUID = UUID(),
        category: GarmentCategory,
        dominantColor: String? = nil,
        dateWorn: Date,
        thumbnailPath: String
    ) {
        self.id = id
        self.category = category
        self.dominantColor = dominantColor
        self.dateWorn = dateWorn
        self.thumbnailPath = thumbnailPath
    }
}

/// The garment classes the segmentation model can name today.
public enum GarmentCategory: String, CaseIterable, Codable, Sendable {
    case top
    case bottom

    /// Class indices in the FASHN SegFormer output.
    var classIDs: [Int] {
        switch self {
        case .top: [3]
        case .bottom: [6]
        }
    }
}
