import Foundation
import SwiftData
import Testing
@testable import WardrobeKit

@MainActor
struct MediaUploadTests {
    // MARK: - The ordering rule

    @Test func aCompletionIsHeldWhileItsMediaCannotUpload() async throws {
        let sut = makeSUT()
        let owner = UUID()
        try sut.outbox.enqueue(completionMutation(id: owner), at: .distantPast)
        sut.uploads.stage(makeUpload(owner: owner))
        sut.media.error = .network

        _ = await sut.coordinator.reconcile(.manual)

        #expect(sut.client.syncCalls == 0, "the mutation must wait for its media")
        #expect(try sut.outbox.entries().count == 1)
        let row = try #require(try sut.uploads.entries().first)
        #expect(row.attempts == 1)
    }

    @Test func aCompletionIsPushedOnceItsMediaAreUp() async throws {
        let sut = makeSUT()
        let owner = UUID()
        try sut.outbox.enqueue(completionMutation(id: owner), at: .distantPast)
        sut.uploads.stage(makeUpload(owner: owner))
        sut.uploads.stage(makeUpload(owner: owner))

        let outcome = await sut.coordinator.reconcile(.manual)

        #expect(outcome.uploaded == 2)
        #expect(try sut.uploads.entries().isEmpty)
        #expect(sut.client.syncCalls == 1, "drained media unblocks the mutation in the same run")
    }

    @Test func anUploadFailureRetriesWithoutDuplicatingTheMutation() async throws {
        let sut = makeSUT()
        let owner = UUID()
        try sut.outbox.enqueue(completionMutation(id: owner), at: .distantPast)
        sut.uploads.stage(makeUpload(owner: owner))
        sut.media.error = .unavailable

        _ = await sut.coordinator.reconcile(.manual)
        _ = await sut.coordinator.reconcile(.manual)

        #expect(try sut.outbox.entries().count == 1, "a retry must not mint a second mutation")
        let rows = try sut.uploads.entries()
        #expect(rows.count == 1, "nor a second media row")
        #expect(rows.first?.attempts == 1, "backoff holds the second run off")
    }

    @Test func otherMutationsAreNotHeldByAStrangersMedia() async throws {
        let sut = makeSUT()
        try sut.outbox.enqueue(
            OutboxMutation(name: "deleteItem", payload: Data("{}".utf8)), at: .distantPast
        )
        sut.uploads.stage(makeUpload(owner: UUID()))
        sut.media.error = .network

        _ = await sut.coordinator.reconcile(.manual)

        #expect(sut.client.syncCalls == 1)
    }

    @Test func anExpiredSessionDuringUploadSpendsNoAttempt() async throws {
        let sut = makeSUT()
        let owner = UUID()
        try sut.outbox.enqueue(completionMutation(id: owner), at: .distantPast)
        sut.uploads.stage(makeUpload(owner: owner))
        sut.media.error = .sessionExpired

        let outcome = await sut.coordinator.reconcile(.manual)

        #expect(outcome.pushError == .sessionExpired)
        #expect(try sut.uploads.entries().first?.attempts == 0)
        #expect(sut.client.syncCalls == 0)
    }

    // MARK: - The queue's own policy

    @Test func exhaustedUploadsStayVisibleAndManualRetryRevivesThem() throws {
        let uploads = makeInMemoryUploads()
        let row = makeUpload(owner: UUID())
        uploads.stage(row)
        for _ in 0 ..< StoredOutboxRepository.maxAttempts {
            try uploads.recordFailure(of: row.id, error: .network, code: nil, at: .distantPast)
        }

        #expect(try uploads.entries().first?.state == .failed)
        try uploads.retryFailed(at: .distantPast)
        #expect(try uploads.entries().first?.state == .pending)
        #expect(try uploads.due(at: Date(), limit: 10).count == 1)
    }

    // MARK: - The store round-trips every source kind

    @Test func everySourceKindSurvivesTheStore() throws {
        let container = try ModelContainer(
            for: SwiftDataWardrobeItemRepository.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let store = SwiftDataMediaUploadStore(context: ModelContext(container))
        let owner = UUID()
        let photoID = UUID()
        let sources: [MediaUploadSource] = [
            .photoOriginal(photoID),
            .previewFile("a.jpg"),
            .thumbnailFile("b.png"),
            .inline(Data([0x01, 0x02])),
        ]
        for source in sources {
            store.stage(MediaUpload(
                id: UUID(), ownerID: owner, kind: .cutout,
                contentType: "image/png", source: source, createdAt: Date()
            ))
        }

        let restored = try store.all()

        #expect(restored.count == 4)
        #expect(Set(restored.map(\.source)) == Set(sources))
        #expect(try store.hasRows(owner: owner))
        #expect(try store.hasRows(owner: UUID()) == false)
    }

    // MARK: - Fixtures

    private struct SUT {
        let coordinator: ServerSyncCoordinator
        let client: OrderingSyncClient
        let outbox: StoredOutboxRepository
        let uploads: StoredMediaUploadRepository
        let media: StubMediaRepository
    }

    private func makeSUT() -> SUT {
        let client = OrderingSyncClient()
        let outbox = StoredOutboxRepository(store: InMemoryOutboxStore())
        let uploads = makeInMemoryUploads()
        let media = StubMediaRepository()
        return SUT(
            coordinator: ServerSyncCoordinator(
                client: client, outbox: outbox,
                feed: ServerChangeFeedRepository(client: client, cursor: InMemoryCursorStore()),
                uploads: uploads, media: media
            ),
            client: client, outbox: outbox, uploads: uploads, media: media
        )
    }

    private func completionMutation(id: UUID) -> OutboxMutation {
        OutboxMutation(id: id, name: "completeChallenge", payload: Data("{}".utf8))
    }

    private func makeUpload(owner: UUID) -> MediaUpload {
        MediaUpload(
            id: UUID(), ownerID: owner, kind: .cutout, contentType: "image/png",
            source: .inline(Data([0xAB])), createdAt: .distantPast
        )
    }
}

// MARK: - Doubles

@MainActor
private final class OrderingSyncClient: AuthenticatedAPIClient {
    private(set) var syncCalls = 0

    func send<Route: Endpoint>(_ endpoint: Route) async throws -> Route.Response {
        guard endpoint is GetChangesEndpoint else { throw AppError.unexpected }
        return try JSONDecoder.api.decode(
            Route.Response.self, from: Data(#"{"changes":[],"nextSince":0}"#.utf8)
        )
    }

    func send<Route: RequestEndpoint>(_ endpoint: Route) async throws -> Route.Response {
        guard endpoint is PostSyncEndpoint else { throw AppError.unexpected }
        syncCalls += 1
        return try JSONDecoder.api.decode(Route.Response.self, from: Data(#"{"results":[]}"#.utf8))
    }
}
