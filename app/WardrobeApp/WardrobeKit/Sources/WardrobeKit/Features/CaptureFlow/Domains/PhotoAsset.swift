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

/// A library photo, reduced to the only thing that is safe to hand around:
/// its identifier. `PHAsset` itself is not `Sendable`, so it never leaves the
/// browser.
public struct PhotoAsset: Identifiable, Sendable, Equatable {
    public let id: String

    public init(id: String) {
        self.id = id
    }
}
