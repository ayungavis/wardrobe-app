import Foundation
import SwiftData

@MainActor
public protocol DiagnosticsStore: AnyObject, Sendable {
    func record(_ error: Error, context: Log.Context, at date: Date) throws
    func entries() throws -> [DiagnosticEntry]
    func removeAll() throws
}

// MARK: - SwiftData

@MainActor
public final class SwiftDataDiagnosticsStore: DiagnosticsStore {
    public static let limit = 50

    private let context: ModelContext

    // ponytail: its own ModelContext, never the shared one. A diagnostic can be
    // written at any moment, and saving the shared context would commit whatever
    // outbox entry happened to be staged — the one guarantee T35 exists for.
    public init(container: ModelContainer) {
        context = ModelContext(container)
    }

    public func record(_ error: Error, context entry: Log.Context, at date: Date) throws {
        context.insert(DiagnosticEntryEntity(
            message: String(describing: error), context: entry, at: date
        ))
        try trim()
        try context.save()
    }

    public func entries() throws -> [DiagnosticEntry] {
        try context.fetch(Self.newestFirst()).map(\.domain)
    }

    public func removeAll() throws {
        try context.delete(model: DiagnosticEntryEntity.self)
        try context.save()
    }

    private func trim() throws {
        let stored = try context.fetch(Self.newestFirst())
        guard stored.count > Self.limit else { return }
        for entity in stored.dropFirst(Self.limit) {
            context.delete(entity)
        }
    }

    private static func newestFirst() -> FetchDescriptor<DiagnosticEntryEntity> {
        FetchDescriptor<DiagnosticEntryEntity>(sortBy: [SortDescriptor(\.at, order: .reverse)])
    }
}

// MARK: - Storage entity

@Model
final class DiagnosticEntryEntity {
    #Unique<DiagnosticEntryEntity>([\.id])
    private(set) var id: UUID = UUID()
    var at: Date = Date()
    var message: String = ""
    var operation: String?
    var endpoint: String?
    var requestID: String?
    var status: Int?

    init(message: String, context: Log.Context, at: Date) {
        id = UUID()
        self.at = at
        self.message = message
        operation = context.operation
        endpoint = context.endpoint
        requestID = context.requestID
        status = context.status
    }

    var domain: DiagnosticEntry {
        DiagnosticEntry(
            id: id, at: at, message: message, operation: operation,
            endpoint: endpoint, requestID: requestID, status: status
        )
    }
}
