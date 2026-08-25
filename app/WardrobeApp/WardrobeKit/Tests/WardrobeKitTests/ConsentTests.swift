import Foundation
import Testing
@testable import WardrobeKit

@MainActor
struct ConsentTests {
    // MARK: - The gate

    @Test func noUploadStartsBeforeConsentIsDecided() async throws {
        let sut = makeSUT(consent: nil)
        sut.uploads.stage(makeUpload(owner: UUID()))

        let outcome = await sut.coordinator.reconcile(.manual)

        #expect(sut.media.uploadedIDs.isEmpty, "no bytes may leave the device before consent")
        #expect(outcome.uploaded == 0)
        #expect(try sut.uploads.entries().first?.attempts == 0, "waiting is not a failure")
    }

    @Test func grantOpensTheGateOnTheNextReconcile() async throws {
        let sut = makeSUT(consent: nil)
        sut.uploads.stage(makeUpload(owner: UUID()))

        _ = await sut.coordinator.reconcile(.manual)
        var stored = sut.preferences.load()
        stored.uploadConsentAt = Date()
        sut.preferences.save(stored)
        let outcome = await sut.coordinator.reconcile(.manual)

        #expect(outcome.uploaded == 1)
        #expect(try sut.uploads.entries().isEmpty)
    }

    @Test func anUndecidedConsentAlsoHoldsTheCompletionMutation() async throws {
        let sut = makeSUT(consent: nil)
        let owner = UUID()
        try sut.outbox.enqueue(
            OutboxMutation(id: owner, name: "completeChallenge", payload: Data("{}".utf8)),
            at: .distantPast
        )
        sut.uploads.stage(makeUpload(owner: owner))

        _ = await sut.coordinator.reconcile(.manual)

        #expect(sut.client.syncCalls == 0, "the canvas text waits with its media")
        #expect(try sut.outbox.entries().count == 1)
    }

    @Test func decliningLeavesTheLocalLoopAndOtherMutationsWorking() async throws {
        let sut = makeSUT(consent: nil, declined: Date())
        try sut.outbox.enqueue(
            OutboxMutation(name: "deleteItem", payload: Data("{}".utf8)), at: .distantPast
        )
        sut.uploads.stage(makeUpload(owner: UUID()))

        let outcome = await sut.coordinator.reconcile(.manual)

        #expect(sut.media.uploadedIDs.isEmpty)
        #expect(sut.client.syncCalls == 1, "declining media consent does not stop the rest of sync")
        #expect(outcome.pushed == 0)
        #expect(try sut.uploads.entries().count == 1, "held, visible, never dropped")
    }

    // MARK: - The stamps

    @Test func grantingTwiceKeepsTheFirstDate() {
        let preferences = InMemoryAccountPreferencesRepository()
        let first = Date(timeIntervalSince1970: 100)

        var stored = preferences.load()
        stored.uploadConsentAt = stored.uploadConsentAt ?? first
        preferences.save(stored)
        var again = preferences.load()
        again.uploadConsentAt = again.uploadConsentAt ?? Date()
        preferences.save(again)

        #expect(preferences.load().uploadConsentAt == first)
    }

    @Test func theDeclineStampStaysOnTheDevice() throws {
        let json = try JSONEncoder().encode(AccountPreferences(
            uploadConsentAt: Date(), uploadConsentDeclinedAt: Date()
        ))
        let args = UpsertPreferencesArgsDTO(
            onboardingCompletedAt: nil, uploadConsentAt: Date(), recentStickerIds: []
        )
        let wire = try #require(String(bytes: JSONEncoder.api.encode(args), encoding: .utf8))

        #expect(!wire.contains("Declined"), "the server has no field for a refusal")
        _ = json
    }

    @Test func consentSurvivesTheStoredRoundTrip() throws {
        let stamped = AccountPreferences(uploadConsentAt: Date(timeIntervalSince1970: 500))
        let data = try JSONEncoder().encode(stamped)
        let restored = try JSONDecoder().decode(AccountPreferences.self, from: data)

        #expect(restored.uploadConsentAt == stamped.uploadConsentAt)
    }

    // MARK: - Fixtures

    private struct SUT {
        let coordinator: ServerSyncCoordinator
        let client: GateSyncClient
        let outbox: StoredOutboxRepository
        let uploads: StoredMediaUploadRepository
        let media: StubMediaRepository
        let preferences: InMemoryAccountPreferencesRepository
    }

    private func makeSUT(consent: Date?, declined: Date? = nil) -> SUT {
        let client = GateSyncClient()
        let outbox = StoredOutboxRepository(store: InMemoryOutboxStore())
        let uploads = makeInMemoryUploads()
        let media = StubMediaRepository()
        let preferences = InMemoryAccountPreferencesRepository()
        preferences.stored = AccountPreferences(
            uploadConsentAt: consent, uploadConsentDeclinedAt: declined
        )
        return SUT(
            coordinator: ServerSyncCoordinator(
                client: client, outbox: outbox,
                feed: ServerChangeFeedRepository(client: client, cursor: InMemoryCursorStore()),
                uploads: uploads, media: media,
                preferences: preferences
            ),
            client: client, outbox: outbox, uploads: uploads, media: media, preferences: preferences
        )
    }

    private func makeUpload(owner: UUID) -> MediaUpload {
        MediaUpload(
            id: UUID(), ownerID: owner, kind: .cutout, contentType: "image/png",
            source: .inline(Data([0xCD])), createdAt: .distantPast
        )
    }
}

// MARK: - Doubles

@MainActor
private final class GateSyncClient: AuthenticatedAPIClient {
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
