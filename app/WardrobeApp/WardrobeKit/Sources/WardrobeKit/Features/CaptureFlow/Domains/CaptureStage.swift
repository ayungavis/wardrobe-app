import Foundation

public enum CaptureStage: Equatable {
    case consent
    case denied
    case camera
    /// Framing the capture to 3:4 before it reaches the editor (FR-083).
    case crop
    case editor
}
