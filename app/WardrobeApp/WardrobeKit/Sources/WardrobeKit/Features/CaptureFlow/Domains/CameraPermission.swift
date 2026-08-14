import Foundation

public enum CameraPermission: Equatable, Sendable {
    case notDetermined
    case granted
    case denied
    case restricted
}
