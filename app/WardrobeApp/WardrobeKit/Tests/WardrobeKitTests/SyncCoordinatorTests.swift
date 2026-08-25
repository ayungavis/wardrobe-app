import Foundation
import Testing
@testable import WardrobeKit

@MainActor
struct SyncCoordinatorTests {
    // MARK: - Single flight

    @Test func twoTriggersAtOnceProduceOneRun() async throws {
        let sut = try makeSUT()
        try sut.outbox.enqueue(makeMutation(), at: .distantPast)

        async let first = sut.coordinator.reconcile(.foreground)
        async let second = sut.coordinator.reconcile(.manual)
        _ = await (first, second)

        #expect(sut.client.syncCalls == 1)
    }

    // MARK: - Push

    @Test func anAppliedLineLeavesTheQueue() async throws {
        let sut = try makeSUT()
        let mutation = makeMutation()
        try sut.outbox.enqueue(mutation, at: .distantPast)
        sut.client.syncResults = [StubSyncClient.Line(id: mutation.id, name: "deleteItem")]

        let outcome = await sut.coordinator.reconcile(.manual)

        #expect(outcome.pushed == 1)
        #expect(try sut.outbox.entries().isEmpty)
    }

    @Test func aRejectedLineStaysWithTheServersOwnCode() async throws {
        let sut = try makeSUT()
        let mutation = makeMutation()
        try sut.outbox.enqueue(mutation, at: .distantPast)
        sut.client.syncResults = [StubSyncClient.Line(id: mutation.id, name: "deleteItem", failure: "not_found")]

        let outcome = await sut.coordinator.reconcile(.manual)

        #expect(outcome.rejected == 1)
        let entry = try #require(try sut.outbox.entries().first)
        #expect(entry.lastErrorCode == "not_found")
        #expect(entry.attempts == 1)
    }

    @Test func anExpiredSessionSpendsNoAttempt() async throws {
        let sut = try makeSUT()
        let mutation = makeMutation()
        try sut.outbox.enqueue(mutation, at: .distantPast)
        sut.client.syncError = .sessionExpired

        let outcome = await sut.coordinator.reconcile(.manual)

        #expect(outcome.pushError == .sessionExpired)
        let entry = try #require(try sut.outbox.entries().first)
        #expect(entry.attempts == 0)
        #expect(entry.state == .pending)
    }

    @Test func aTransportFailureSpendsOneAttempt() async throws {
        let sut = try makeSUT()
        let mutation = makeMutation()
        try sut.outbox.enqueue(mutation, at: .distantPast)
        sut.client.syncError = .network

        _ = await sut.coordinator.reconcile(.manual)

        let entry = try #require(try sut.outbox.entries().first)
        #expect(entry.attempts == 1)
        #expect(entry.lastErrorCode == "network")
    }

    @Test func anExhaustedEntryIsNotPushedAgain() async throws {
        let sut = try makeSUT()
        let mutation = makeMutation()
        try sut.outbox.enqueue(mutation, at: .distantPast)
        for _ in 0 ..< StoredOutboxRepository.maxAttempts {
            try sut.outbox.recordFailure(of: mutation.id, error: .network, at: .distantPast)
        }
        sut.client.syncCalls = 0

        let outcome = await sut.coordinator.reconcile(.manual)

        #expect(sut.client.syncCalls == 0)
        #expect(outcome.pushed == 0)
        #expect(try sut.outbox.entries().first?.state == .failed)
    }

    // MARK: - Push and pull are independent

    @Test func aFailedPushStillLetsThePullThrough() async throws {
        let sut = try makeSUT()
        try sut.outbox.enqueue(makeMutation(), at: .distantPast)
        sut.client.syncError = .network

        let outcome = await sut.coordinator.reconcile(.manual)

        #expect(outcome.pushError != nil)
        #expect(sut.client.changesCalls == 2)
        #expect(try sut.cursor.position() == 2)
    }

    @Test func anEmptyQueueSendsNoMutationAtAll() async throws {
        let sut = try makeSUT()

        let outcome = await sut.coordinator.reconcile(.foreground)

        #expect(sut.client.syncCalls == 0)
        #expect(outcome.pushed == 0)
        #expect(sut.client.changesCalls == 2)
    }

    // MARK: - Every trigger reaches the same run

    @Test func everyTriggerStartsExactlyOneReconciliation() async throws {
        for trigger in SyncTrigger.allCases {
            let sut = try makeSUT()
            _ = await sut.coordinator.reconcile(trigger)
            #expect(sut.client.changesCalls == 2, "\(trigger.rawValue) should reconcile once")
        }
    }

    // MARK: - Connectivity is an edge, not a level

    @Test func onlyTheReturnFromOfflineCounts() {
        var edge = ReachabilityEdge()
        let path = [true, true, false, true, true]

        let recoveries = path.filter { edge.recovered(isSatisfied: $0) }.count

        #expect(recoveries == 1)
    }

    @Test func aRunOfSatisfiedUpdatesNeverFires() {
        var edge = ReachabilityEdge()

        let recoveries = [true, true, true, true].filter { edge.recovered(isSatisfied: $0) }.count

        #expect(recoveries == 0)
    }

    @Test func everyReturnFromOfflineFiresOnceEach() {
        var edge = ReachabilityEdge()

        let recoveries = [false, true, false, true, false, true]
            .filter { edge.recovered(isSatisfied: $0) }.count

        #expect(recoveries == 3)
    }

    // MARK: - Fixtures

    private struct SUT {
        let coordinator: ServerSyncCoordinator
        let client: StubSyncClient
        let outbox: StoredOutboxRepository
        let cursor: InMemoryCursorStore
    }

    private func makeSUT() throws -> SUT {
        let client = StubSyncClient()
        let outbox = StoredOutboxRepository(store: InMemoryOutboxStore())
        let cursor = InMemoryCursorStore()
        let feed = ServerChangeFeedRepository(client: client, cursor: cursor)
        return SUT(
            coordinator: ServerSyncCoordinator(
                client: client, outbox: outbox, feed: feed,
                uploads: makeInMemoryUploads(), media: StubMediaRepository()
            ),
            client: client, outbox: outbox, cursor: cursor
        )
    }

    private func makeMutation() -> OutboxMutation {
        OutboxMutation(name: "deleteItem", payload: Data(#"{"id":"x"}"#.utf8))
    }
}

// MARK: - Doubles

@MainActor
private final class StubSyncClient: AuthenticatedAPIClient {
    var syncCalls = 0
    var changesCalls = 0
    var syncError: AppError?
    struct Line {
        let id: UUID
        let name: String
        var failure: String?
    }

    var syncResults: [Line] = []

    func send<Route: Endpoint>(_ endpoint: Route) async throws -> Route.Response {
        guard endpoint is GetChangesEndpoint else { throw AppError.unexpected }
        changesCalls += 1
        let json = changesCalls == 1
            ? #"""
            {"changes":[{"kind":"newerKind","changeSeq":1,"record":{}},
                        {"kind":"newerKind","changeSeq":2,"record":{}}],"nextSince":2}
            """#
            : #"{"changes":[],"nextSince":2}"#
        return try JSONDecoder.api.decode(Route.Response.self, from: Data(json.utf8))
    }

    func send<Route: RequestEndpoint>(_ endpoint: Route) async throws -> Route.Response {
        guard endpoint is PostSyncEndpoint else { throw AppError.unexpected }
        syncCalls += 1
        if let syncError {
            throw syncError
        }
        let lines = syncResults.map { result in
            if let failure = result.failure {
                #"""
                {"id":"\#(result.id.uuidString)","name":"\#(result.name)","status":"failed",
                 "error":{"code":"\#(failure)","message":"m"}}
                """#
            } else {
                #"""
                {"id":"\#(result.id.uuidString)","name":"\#(result.name)",
                 "status":"applied","record":{}}
                """#
            }
        }
        let json = #"{"results":[\#(lines.joined(separator: ","))]}"#
        return try JSONDecoder.api.decode(Route.Response.self, from: Data(json.utf8))
    }
}
