import Foundation

public enum PhotoSaveState: Equatable, Sendable {
    case idle
    case saving
    case saved
}
