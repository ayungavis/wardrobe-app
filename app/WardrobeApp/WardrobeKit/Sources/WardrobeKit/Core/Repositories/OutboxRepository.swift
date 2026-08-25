import Foundation

public struct OutboxMutation: Sendable, Equatable {
    public let id: UUID
    public let name: String
    public let payload: Data

    public init(id: UUID = UUID(), name: String, payload: Data) {
        self.id = id
        self.name = name
        self.payload = payload
    }
}

@MainActor
public protocol OutboxRepository: AnyObject {
    func stage(_ mutation: OutboxMutation, at date: Date)
    func enqueue(_ mutation: OutboxMutation, at date: Date) throws
    func enqueueReplacing(_ mutation: OutboxMutation, at date: Date) throws
    func entries() throws -> [OutboxEnvelope]
    func due(at date: Date, limit: Int) throws -> [OutboxEnvelope]
    func acknowledge(id: UUID) throws
    func recordFailure(of id: UUID, error: AppError, at date: Date) throws
    func retryFailed(at date: Date) throws
    func removeAll() throws
}

public extension OutboxRepository {
    func stage(_ mutation: OutboxMutation) {
        stage(mutation, at: Date())
    }

    func enqueue(_ mutation: OutboxMutation) throws {
        try enqueue(mutation, at: Date())
    }
}

@MainActor
public final class StoredOutboxRepository: OutboxRepository {
    // ponytail: 5s doubling to a 5-minute ceiling over 5 attempts, so exhaustion
    // lands near 2.5 minutes. It is the shape services/crates/worker/src/lib.rs
    // already uses, with client numbers because a sync mutation is cheap and sits
    // in front of the user. Move these from a measurement, not from taste.
    static let maxAttempts = 5
    static let baseDelay: TimeInterval = 5
    static let maxDelay: TimeInterval = 300

    private let store: any OutboxStore

    public init(store: any OutboxStore) {
        self.store = store
    }

    public func stage(_ mutation: OutboxMutation, at date: Date) {
        store.stage(Self.envelope(for: mutation, at: date))
    }

    public func enqueue(_ mutation: OutboxMutation, at date: Date) throws {
        try store.append(Self.envelope(for: mutation, at: date))
    }

    // ponytail: only sound for a mutation that sends whole state, such as
    // upsertPreferences, where an older queued copy says nothing the newer one
    // does not. A per-field mutation must never use this.
    public func enqueueReplacing(_ mutation: OutboxMutation, at date: Date) throws {
        for superseded in try store.all() where superseded.name == mutation.name {
            try store.remove(id: superseded.id)
        }
        try enqueue(mutation, at: date)
    }

    public func entries() throws -> [OutboxEnvelope] {
        try store.all()
    }

    public func due(at date: Date, limit: Int) throws -> [OutboxEnvelope] {
        try store.due(at: date, limit: limit)
    }

    public func acknowledge(id: UUID) throws {
        try store.remove(id: id)
    }

    public func recordFailure(of id: UUID, error: AppError, at date: Date) throws {
        guard var envelope = try store.all().first(where: { $0.id == id }) else {
            throw AppError.unexpected
        }

        envelope.attempts += 1
        envelope.lastErrorCode = Self.code(for: error)
        if envelope.attempts >= Self.maxAttempts {
            envelope.state = .failed
        } else {
            envelope.nextAttemptAt = date.addingTimeInterval(Self.delay(afterAttempt: envelope.attempts))
        }
        try store.update(envelope)
    }

    public func retryFailed(at date: Date) throws {
        for var envelope in try store.all() where envelope.state == .failed {
            envelope.state = .pending
            envelope.attempts = 0
            envelope.nextAttemptAt = date
            try store.update(envelope)
        }
    }

    public func removeAll() throws {
        try store.removeAll()
    }

    static func delay(afterAttempt attempts: Int) -> TimeInterval {
        let exponent = max(0, min(attempts - 1, 16))
        return min(baseDelay * pow(2, Double(exponent)), maxDelay)
    }

    private static func envelope(for mutation: OutboxMutation, at date: Date) -> OutboxEnvelope {
        OutboxEnvelope(
            id: mutation.id,
            name: mutation.name,
            payload: mutation.payload,
            createdAt: date,
            nextAttemptAt: date
        )
    }

    private static func code(for error: AppError) -> String {
        switch error {
        case .network: "network"
        case .sessionExpired: "session_expired"
        case .serverRejected: "server_rejected"
        case .badRequest: "bad_request"
        case .conflict: "conflict"
        case .rateLimited: "rate_limited"
        case .unavailable: "unavailable"
        default: "unexpected"
        }
    }
}
