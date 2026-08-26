import Foundation

public enum SyncState: Equatable, Sendable {
    case localOnly
    case pending
    case failed(code: String, reference: UUID)
    case synced

    public static func derive(
        queuedAt: Date?,
        mutation: OutboxEnvelope?,
        mediaRows: [MediaUpload]
    ) -> SyncState {
        guard queuedAt != nil else { return .localOnly }

        if case .failed = mutation?.state, let mutation {
            return .failed(code: mutation.lastErrorCode ?? "unknown", reference: mutation.id)
        }
        if let broken = mediaRows.first(where: { $0.state == .failed }) {
            return .failed(code: broken.lastErrorCode ?? "unknown", reference: broken.id)
        }
        if mutation != nil || !mediaRows.isEmpty {
            return .pending
        }

        return .synced
    }
}

public extension SyncState {
    var label: String {
        switch self {
        case .localOnly: String(localized: "sync.state.localOnly", bundle: .module)
        case .pending: String(localized: "sync.state.pending", bundle: .module)
        case .failed: String(localized: "sync.state.failed", bundle: .module)
        case .synced: String(localized: "sync.state.synced", bundle: .module)
        }
    }

    var diagnostic: String? {
        guard case let .failed(code, reference) = self else { return nil }
        return "\(code) · \(reference.uuidString.prefix(8))"
    }
}
