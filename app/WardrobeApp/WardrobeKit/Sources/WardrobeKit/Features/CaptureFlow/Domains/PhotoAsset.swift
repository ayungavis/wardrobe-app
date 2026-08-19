import Foundation

public enum PhotoLibraryAccess: Sendable, Equatable {
    case notDetermined
    case authorized
    case limited
    case denied

    public var canBrowse: Bool {
        self == .authorized || self == .limited
    }
}

public struct PhotoAsset: Identifiable, Sendable, Equatable {
    public let id: String

    public init(id: String) {
        self.id = id
    }
}
