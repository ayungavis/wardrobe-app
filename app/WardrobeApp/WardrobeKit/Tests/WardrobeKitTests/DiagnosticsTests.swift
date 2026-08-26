import Foundation
import SwiftData
import Synchronization
import Testing
@testable import WardrobeKit

@MainActor
struct DiagnosticsTests {
    // MARK: - The request id has to survive the trip

    @Test func aFailedResponseReportsTheRequestIdItCameWith() async throws {
        let reports = Recorder()
        Log.diagnosticsSink = { reports.add($1) }
        defer { Log.diagnosticsSink = nil }

        let server = StubServer()
        server.stub(
            "/health",
            StubbedReply.json(#"{"error":{"code":"internal","message":"m"}}"#, status: 500)
                .with(header: "x-request-id", "abc-123")
        )
        let client = URLSessionAPIClient(baseURL: base, session: server.session)

        _ = try? await client.send(GetHealthEndpoint())

        // The sink is global and Swift Testing runs suites in parallel, so this
        // picks its own request out rather than trusting whatever landed last.
        let context = try #require(reports.matching(requestID: "abc-123"))
        #expect(context.requestID == "abc-123")
        #expect(context.status == 500)
        #expect(context.endpoint == "health")
    }

    // MARK: - The context cannot carry user content

    @Test func theContextHasOnlyTheFourNamedFields() {
        let fields = Mirror(reflecting: Log.Context()).children.compactMap(\.label)

        #expect(fields.sorted() == ["endpoint", "operation", "requestID", "status"])
    }

    // MARK: - The rolling buffer

    @Test func theBufferKeepsOnlyTheNewestFifty() throws {
        let store = try makeStore()

        for index in 0 ..< 60 {
            try store.record(
                AppError.network,
                context: Log.Context(operation: "op-\(index)"),
                at: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }

        let entries = try store.entries()
        #expect(entries.count == SwiftDataDiagnosticsStore.limit)
        #expect(entries.first?.operation == "op-59")
        #expect(entries.last?.operation == "op-10")
    }

    @Test func anEntrySurvivesTheStoreBeingReopened() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("diagnostics-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }

        try {
            let container = try ModelContainer(
                for: SwiftDataWardrobeItemRepository.schema,
                configurations: ModelConfiguration(url: url)
            )
            try SwiftDataDiagnosticsStore(container: container).record(
                AppError.serverRejected,
                context: Log.Context(endpoint: "v1/sync", requestID: "kept-42", status: 500),
                at: Date()
            )
        }()

        let reopened = try ModelContainer(
            for: SwiftDataWardrobeItemRepository.schema,
            configurations: ModelConfiguration(url: url)
        )
        let entries = try SwiftDataDiagnosticsStore(container: reopened).entries()

        #expect(entries.count == 1)
        #expect(entries.first?.requestID == "kept-42")
        #expect(entries.first?.status == 500)
    }

    @Test func clearingLeavesNothingBehind() throws {
        let store = try makeStore()
        try store.record(AppError.network, context: Log.Context(), at: Date())

        try store.removeAll()

        #expect(try store.entries().isEmpty)
    }

    // MARK: - Fixtures

    private func makeStore() throws -> SwiftDataDiagnosticsStore {
        let container = try ModelContainer(
            for: SwiftDataWardrobeItemRepository.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return SwiftDataDiagnosticsStore(container: container)
    }

    private var base: URL {
        URL(string: "https://stub.invalid")!
    }
}

/// Log.trail runs off the main actor, so this cannot assume isolation.
private final class Recorder: Sendable {
    private let contexts = Mutex<[Log.Context]>([])

    func matching(requestID: String) -> Log.Context? {
        contexts.withLock { $0.first { $0.requestID == requestID } }
    }

    func add(_ context: Log.Context) {
        contexts.withLock { $0.append(context) }
    }
}
