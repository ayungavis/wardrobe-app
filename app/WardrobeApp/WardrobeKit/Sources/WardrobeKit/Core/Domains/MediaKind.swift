import Foundation

public enum MediaKind: String, CaseIterable, Sendable {
    case original
    case derivative
    case cutout
    case illustration
    case document
    case history

    public var uploadCap: Int {
        switch self {
        case .original: 25 * 1024 * 1024
        case .derivative, .illustration: 10 * 1024 * 1024
        case .cutout, .history: 5 * 1024 * 1024
        case .document: 2 * 1024 * 1024
        }
    }
}
