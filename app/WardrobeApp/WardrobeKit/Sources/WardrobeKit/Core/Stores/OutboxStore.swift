import Foundation
import SwiftData

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

@MainActor
public protocol OutboxStore: AnyObject {
    func stage(_ envelope: OutboxEnvelope)
    func append(_ envelope: OutboxEnvelope) throws
    func all() throws -> [OutboxEnvelope]
    func due(at date: Date, limit: Int) throws -> [OutboxEnvelope]
    func update(_ envelope: OutboxEnvelope) throws
    func remove(id: UUID) throws
    func removeAll() throws
}

// MARK: - SwiftData

@MainActor
public final class SwiftDataOutboxStore: OutboxStore {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public static var schema: Schema {
        Schema([OutboxEntryEntity.self])
    }

    public func stage(_ envelope: OutboxEnvelope) {
        context.insert(OutboxEntryEntity(envelope))
    }

    public func append(_ envelope: OutboxEnvelope) throws {
        stage(envelope)
        try context.save()
    }

    public func all() throws -> [OutboxEnvelope] {
        try context.fetch(Self.ordered()).map(\.domain)
    }

    public func due(at date: Date, limit: Int) throws -> [OutboxEnvelope] {
        let pending = OutboxEnvelope.State.pending.rawValue
        var descriptor = Self.ordered(
            matching: #Predicate { $0.state == pending && $0.nextAttemptAt <= date }
        )
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor).map(\.domain)
    }

    public func update(_ envelope: OutboxEnvelope) throws {
        guard let entity = try entity(id: envelope.id) else {
            throw AppError.unexpected
        }
        entity.apply(envelope)
        try context.save()
    }

    public func remove(id: UUID) throws {
        try context.delete(model: OutboxEntryEntity.self, where: #Predicate { $0.id == id })
        try context.save()
    }

    public func removeAll() throws {
        try context.delete(model: OutboxEntryEntity.self)
        try context.save()
    }

    private func entity(id: UUID) throws -> OutboxEntryEntity? {
        try context.fetch(Self.ordered(matching: #Predicate { $0.id == id })).first
    }

    private static func ordered(
        matching predicate: Predicate<OutboxEntryEntity>? = nil
    ) -> FetchDescriptor<OutboxEntryEntity> {
        FetchDescriptor<OutboxEntryEntity>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
    }
}

// MARK: - Storage entity

@Model
final class OutboxEntryEntity {
    #Unique<OutboxEntryEntity>([\.id])
    private(set) var id: UUID = UUID()
    var name: String = ""
    var payload: Data = Data()
    var createdAt: Date = Date()
    var attempts: Int = 0
    var state: String = OutboxEnvelope.State.pending.rawValue
    var nextAttemptAt: Date = Date()
    var lastErrorCode: String?

    init(_ envelope: OutboxEnvelope) {
        id = envelope.id
        name = envelope.name
        payload = envelope.payload
        createdAt = envelope.createdAt
        apply(envelope)
    }

    func apply(_ envelope: OutboxEnvelope) {
        attempts = envelope.attempts
        state = envelope.state.rawValue
        nextAttemptAt = envelope.nextAttemptAt
        lastErrorCode = envelope.lastErrorCode
    }

    var domain: OutboxEnvelope {
        OutboxEnvelope(
            id: id,
            name: name,
            payload: payload,
            createdAt: createdAt,
            attempts: attempts,
            state: OutboxEnvelope.State(rawValue: state) ?? .pending,
            nextAttemptAt: nextAttemptAt,
            lastErrorCode: lastErrorCode
        )
    }
}
