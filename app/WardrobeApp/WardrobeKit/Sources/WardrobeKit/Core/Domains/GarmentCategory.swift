import Foundation

public enum GarmentCategory: String, CaseIterable, Codable, Sendable {
    case top
    case bottom

    var classIDs: [Int] {
        switch self {
        case .top: [3]
        case .bottom: [6]
        }
    }

    public var defaultName: String {
        switch self {
        case .top: "Top"
        case .bottom: "Bottom"
        }
    }
}
