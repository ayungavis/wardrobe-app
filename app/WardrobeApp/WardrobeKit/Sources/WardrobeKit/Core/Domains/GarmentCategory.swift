import Foundation

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
