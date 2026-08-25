import Foundation

public enum AppError: Error, Equatable, Sendable {
    case network
    case sessionExpired
    case serverRejected
    case badRequest
    case notFound
    case conflict
    case payloadTooLarge
    case rateLimited(retryAfter: Duration)
    case unavailable
    case unexpected
    case cameraUnavailable
    case captureFailed
    case photoImportFailed
    case exportFailed
    case photoSaveFailed
    case photoAccessDenied
    case documentFromNewerApp

    public var userMessage: String {
        switch self {
        case .network:
            String(localized: "error.network", bundle: .module)
        case .sessionExpired:
            String(localized: "error.sessionExpired", bundle: .module)
        case .serverRejected:
            String(localized: "error.serverRejected", bundle: .module)
        case .badRequest:
            String(localized: "error.badRequest", bundle: .module)
        case .notFound:
            String(localized: "error.notFound", bundle: .module)
        case .conflict:
            String(localized: "error.conflict", bundle: .module)
        case .payloadTooLarge:
            String(localized: "error.payloadTooLarge", bundle: .module)
        case .rateLimited:
            String(localized: "error.rateLimited", bundle: .module)
        case .unavailable:
            String(localized: "error.unavailable", bundle: .module)
        case .unexpected:
            String(localized: "error.unexpected", bundle: .module)
        case .cameraUnavailable:
            String(localized: "error.cameraUnavailable", bundle: .module)
        case .captureFailed:
            String(localized: "error.captureFailed", bundle: .module)
        case .photoImportFailed:
            String(localized: "error.photoImportFailed", bundle: .module)
        case .exportFailed:
            String(localized: "error.exportFailed", bundle: .module)
        case .photoSaveFailed:
            String(localized: "error.photoSaveFailed", bundle: .module)
        case .photoAccessDenied:
            String(localized: "error.photoAccessDenied", bundle: .module)
        case .documentFromNewerApp:
            String(localized: "error.documentFromNewerApp", bundle: .module)
        }
    }

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
