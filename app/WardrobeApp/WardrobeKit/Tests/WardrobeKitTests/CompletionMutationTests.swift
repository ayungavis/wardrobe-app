import CoreGraphics
import Foundation
import SwiftData
import Testing
@testable import WardrobeKit

@MainActor
struct CompletionMutationTests {
    // MARK: - The migration

    @Test func oldCompletionsArriveAndTheOldKeyIsDropped() throws {
        let defaults = try makeDefaults("completions.migrate")
        let legacy = UserDefaultsCompletedChallengeRepository(defaults: defaults)
        legacy.append(makeCompletion())
        legacy.append(makeCompletion())
        let store = try makeStore()

        let moved = migrateCompletions(from: legacy, into: store, defaults: defaults)

        #expect(moved == 2)
        #expect(store.load().count == 2)
        #expect(legacy.load().isEmpty)
    }

    @Test func theMigrationRunsOnlyOnce() throws {
        let defaults = try makeDefaults("completions.once")
        let legacy = UserDefaultsCompletedChallengeRepository(defaults: defaults)
        legacy.append(makeCompletion())
        let store = try makeStore()

        #expect(migrateCompletions(from: legacy, into: store, defaults: defaults) == 1)
        legacy.append(makeCompletion())
        #expect(migrateCompletions(from: legacy, into: store, defaults: defaults) == 0)
        #expect(store.load().count == 1)
    }

    @Test func aFailedWriteLeavesTheOldDataWhereItWas() throws {
        let defaults = try makeDefaults("completions.failed")
        let legacy = UserDefaultsCompletedChallengeRepository(defaults: defaults)
        legacy.append(makeCompletion())
        let store = RefusingCompletionStore()

        let moved = migrateCompletions(from: legacy, into: store, defaults: defaults)

        #expect(moved == 0)
        #expect(legacy.load().count == 1, "a write that failed must not take the old data with it")
        #expect(defaults.bool(forKey: "completedChallenges.migratedToSwiftData") == false)
    }

    // MARK: - Storage round trip

    @Test func aCompletionSurvivesTheStoreBeingReopened() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "completions-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }
        let completion = makeCompletion()

        try {
            let container = try ModelContainer(
                for: SwiftDataWardrobeItemRepository.schema,
                configurations: ModelConfiguration(url: url)
            )
            SwiftDataCompletedChallengeRepository(context: ModelContext(container)).append(completion)
        }()

        let reopened = try ModelContainer(
            for: SwiftDataWardrobeItemRepository.schema,
            configurations: ModelConfiguration(url: url)
        )
        let restored = SwiftDataCompletedChallengeRepository(context: ModelContext(reopened)).load()

        #expect(restored.count == 1)
        #expect(restored.first?.id == completion.id)
        #expect(restored.first?.card.id == completion.card.id)
    }

    @Test func aSecondCompletionOnTheSameDayIsKeptNotDropped() throws {
        let store = try makeStore()
        let day = Date()

        store.append(makeCompletion(at: day))
        store.append(makeCompletion(at: day))

        #expect(store.load().count == 2, "FR-065 preserves the second as a conflict")
    }

    // MARK: - The mutation

    @Test func theMutationIdIsTheCompletionIdSoAReplayCollides() throws {
        let completion = makeCompletion()
        let args = try CompletionSyncPlanner.plan(for: completion, items: [], at: Date()).args
        let queued = try SyncMutation.completeChallenge(args).queued(id: completion.id)

        #expect(queued.id == completion.id)
        #expect(queued.name == "completeChallenge")
    }

    @Test func theArgumentsCarryTheDevicesOwnDateAndZone() throws {
        let completion = makeCompletion()
        let args = try CompletionSyncPlanner.plan(for: completion, items: [], at: Date()).args
        #expect(args.timeZone == TimeZone.current.identifier)
        #expect(args.localDate.count == 10)
        #expect(args.completionId == completion.id)
        #expect(args.cardId == completion.card.id)
    }

    // MARK: - One checkmark, one entry

    @Test func oneCheckmarkQueuesExactlyOneEntry() async throws {
        let sut = try makeTransactionalCaptureFlow()

        await sut.flow.commit()

        let entries = try sut.outbox.entries()
        #expect(entries.count == 1)
        #expect(entries.first?.name == "completeChallenge")
        #expect(sut.completions.load().count == 1)
        let rows = try sut.uploads.entries()
        #expect(rows.count == 3, "photo, derivative, document — no garments in this flow")
        #expect(rows.allSatisfy { $0.ownerID == entries.first?.id })
    }

    @Test func aCheckmarkThatFailsLeavesNeitherRowsNorAnEntry() async throws {
        let scanner = FakeGarmentScanService()
        scanner.result = [makeDiscardedGarment()]
        let sut = try makeTransactionalCaptureFlow(
            scanner: scanner, thumbnails: RefusingThumbnailRepository()
        )
        sut.flow.review.scan(photo: Data([0x01]))
        await sut.flow.review.finishScanning()

        await sut.flow.commit()

        #expect(try sut.outbox.entries().isEmpty, "a failed checkmark must queue nothing")
        #expect(sut.completions.load().isEmpty, "and must leave no completion behind")
        #expect(try sut.uploads.entries().isEmpty, "and no media rows either")
        #expect(sut.flow.isCompleted == false)
    }

    // MARK: - FR-088: the last ten undo steps

    @Test func aCompletionWithEditsCarriesItsUndoHistory() throws {
        let steps = [makeCompletion().document, makeCompletion().document]

        let plan = try CompletionSyncPlanner.plan(
            for: makeCompletion(), items: [], at: Date(), history: steps
        )

        #expect(plan.args.document.historyStepCount == 2)
        let mediaID = try #require(plan.args.document.historyMediaObjectId)
        let row = try #require(plan.uploads.first { $0.kind == .history })
        #expect(row.id == mediaID, "the payload and the queue must name the same object")
        #expect(row.contentType == "application/zlib")
    }

    @Test func aCompletionWithNoEditsCarriesNoHistory() throws {
        let plan = try CompletionSyncPlanner.plan(for: makeCompletion(), items: [], at: Date())

        #expect(plan.args.document.historyMediaObjectId == nil)
        #expect(plan.args.document.historyStepCount == nil)
        #expect(!plan.uploads.contains { $0.kind == .history })
    }

    @Test func anOversizedHistoryIsDroppedWithoutHoldingTheCompletion() throws {
        let steps = [makeCompletion().document]
        #expect(UndoHistoryPayload.data(for: steps, cap: 4) == nil)

        let plan = try CompletionSyncPlanner.plan(
            for: makeCompletion(), items: [], at: Date(), history: steps
        )
        #expect(plan.uploads.contains { $0.kind == .document }, "the completion itself still ships")
    }

    @Test func theHistoryPayloadRoundTrips() throws {
        let steps = [makeCompletion().document, makeCompletion().document]
        let compressed = try #require(UndoHistoryPayload.data(for: steps))

        let restored = try JSONDecoder().decode(
            [EditorDocument].self,
            from: (compressed as NSData).decompressed(using: .zlib) as Data
        )

        #expect(restored == steps)
    }

    // MARK: - Fixtures

    private func makeDefaults(_ name: String) throws -> UserDefaults {
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func makeStore() throws -> SwiftDataCompletedChallengeRepository {
        let container = try ModelContainer(
            for: SwiftDataWardrobeItemRepository.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return SwiftDataCompletedChallengeRepository(context: ModelContext(container))
    }

    private func makeDiscardedGarment() -> ScannedGarment {
        ScannedGarment(
            id: UUID(), name: "coat", description: "", category: .top,
            cutoutFile: "x.png",
            fingerprint: ItemFingerprint(
                itemID: UUID(), version: "v1", colorLab: [0, 0, 0], aspectRatio: 1,
                featurePrint: Data(), maskQuality: 1, createdAt: Date()
            ),
            matches: [], decision: .discard
        )
    }

    private func makeCompletion(at date: Date = Date()) -> CompletedChallenge {
        CompletedChallenge(
            card: ChallengeCard(id: UUID(), prompt: "Wear something blue"),
            photoID: UUID(),
            document: EditorDocument(id: UUID(), layers: []),
            completedAt: date
        )
    }
}

// MARK: - Doubles

final class RefusingThumbnailRepository: GarmentThumbnailRepository, @unchecked Sendable {
    func save(_: CGImage, id _: UUID) throws -> String {
        throw AppError.unexpected
    }

    func data(forFile _: String) throws -> Data {
        throw AppError.unexpected
    }

    func delete(file _: String) throws {
        throw AppError.unexpected
    }

    func deleteAll() throws {}
}

@MainActor
private final class RefusingCompletionStore: CompletedChallengeRepository {
    func load() -> [CompletedChallenge] {
        []
    }

    func append(_: CompletedChallenge) {}

    func removeCompletions(on _: Date) {}

    func removeAll() {}
}

@MainActor
private final class CountingSyncClient: AuthenticatedAPIClient {
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
