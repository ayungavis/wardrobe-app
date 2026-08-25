import Foundation

public struct OutboxEnvelope: Sendable, Equatable, Identifiable {
    public enum State: String, Sendable, CaseIterable {
        case pending
        case failed
    }

    public let id: UUID
    public let name: String
    public let payload: Data
    public let createdAt: Date
    public var attempts: Int
    public var state: State
    public var nextAttemptAt: Date
    public var lastErrorCode: String?

    public init(
        id: UUID,
        name: String,
        payload: Data,
        createdAt: Date,
        attempts: Int = 0,
        state: State = .pending,
        nextAttemptAt: Date,
        lastErrorCode: String? = nil
    ) {
        self.id = id
        self.name = name
        self.payload = payload
        self.createdAt = createdAt
        self.attempts = attempts
        self.state = state
        self.nextAttemptAt = nextAttemptAt
        self.lastErrorCode = lastErrorCode
    }
}
