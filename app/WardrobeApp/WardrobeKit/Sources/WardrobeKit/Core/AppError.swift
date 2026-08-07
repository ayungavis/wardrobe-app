import Foundation

/// Typed app errors with user-facing messages (PRD §17: errors must be
/// specific and actionable, never expose raw internals).
public enum AppError: Error, Equatable, Sendable {
    case network
    case unexpected

    /// Localized message safe to show in UI.
    public var userMessage: String {
        switch self {
        case .network:
            String(localized: "error.network", bundle: .module)
        case .unexpected:
            String(localized: "error.unexpected", bundle: .module)
        }
    }

    /// Maps any thrown error to a typed AppError.
    public init(wrapping error: Error) {
        if let appError = error as? AppError {
            self = appError
        } else if error is URLError {
            self = .network
        } else {
            self = .unexpected
        }
    }
}
