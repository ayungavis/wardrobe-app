import Foundation
import SwiftData
import Testing
@testable import WardrobeKit

@MainActor
struct OutboxTests {
    // MARK: - The transaction claim

    @Test func stagedEntryCommitsWithTheDomainWrite() throws {
        let context = try makeContext()
        let store = SwiftDataOutboxStore(context: context)
        let wardrobe = SwiftDataWardrobeItemRepository(context: context)

        try context.transaction {
            context.insert(WardrobeItemEntity(makeItem()))
            store.stage(makeEnvelope())
        }

        #expect(try store.all().count == 1)
        #expect(try wardrobe.items().count == 1)
    }

    @Test func aRolledBackDomainWriteLeavesNoOutboxEntry() throws {
        let context = try makeContext()
        let store = SwiftDataOutboxStore(context: context)
        let wardrobe = SwiftDataWardrobeItemRepository(context: context)

        context.insert(WardrobeItemEntity(makeItem()))
        store.stage(makeEnvelope())
        context.rollback()

        #expect(try store.all().isEmpty)
        #expect(try wardrobe.items().isEmpty)
    }

    // MARK: - Durability

    @Test func anEntrySurvivesTheStoreBeingReopened() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("outbox-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }
        let id = UUID()

        try {
            let container = try ModelContainer(
                for: SwiftDataWardrobeItemRepository.schema,
                configurations: ModelConfiguration(url: url)
            )
            let store = SwiftDataOutboxStore(context: ModelContext(container))
            try store.append(makeEnvelope(id: id, name: "completeChallenge"))
        }()

        let reopened = try ModelContainer(
            for: SwiftDataWardrobeItemRepository.schema,
            configurations: ModelConfiguration(url: url)
        )
        let entries = try SwiftDataOutboxStore(context: ModelContext(reopened)).all()

        #expect(entries.count == 1)
        #expect(entries.first?.id == id)
        #expect(entries.first?.name == "completeChallenge")
    }

    // MARK: - Retry, exhaustion, and manual retry

    @Test func exhaustedAttemptsStayQueuedAsFailed() throws {
        let repository = try makeRepository()
        let mutation = makeMutation()
        try repository.enqueue(mutation, at: .distantPast)

        for _ in 0 ..< StoredOutboxRepository.maxAttempts {
            try repository.recordFailure(of: mutation.id, error: .network, at: Date())
        }

        let entry = try #require(try repository.entries().first)
        #expect(entry.state == .failed)
        #expect(entry.attempts == StoredOutboxRepository.maxAttempts)
        #expect(entry.lastErrorCode == "network")
        #expect(try repository.entries().count == 1)
    }

    @Test func manualRetryMovesAFailedEntryBackToPending() throws {
        let repository = try makeRepository()
        let mutation = makeMutation()
        try repository.enqueue(mutation, at: .distantPast)
        for _ in 0 ..< StoredOutboxRepository.maxAttempts {
            try repository.recordFailure(of: mutation.id, error: .unavailable, at: Date())
        }

        let now = Date()
        try repository.retryFailed(at: now)

        let entry = try #require(try repository.entries().first)
        #expect(entry.state == .pending)
        #expect(entry.attempts == 0)
        #expect(try repository.due(at: now, limit: 10).count == 1)
    }

    @Test func aFailureBeforeExhaustionSchedulesTheNextAttemptLater() throws {
        let repository = try makeRepository()
        let mutation = makeMutation()
        let now = Date()
        try repository.enqueue(mutation, at: now)

        try repository.recordFailure(of: mutation.id, error: .network, at: now)

        let entry = try #require(try repository.entries().first)
        #expect(entry.state == .pending)
        #expect(entry.nextAttemptAt > now)
        #expect(try repository.due(at: now, limit: 10).isEmpty)
    }

    @Test func backoffDoublesAndStopsAtTheCeiling() {
        #expect(StoredOutboxRepository.delay(afterAttempt: 1) == 5)
        #expect(StoredOutboxRepository.delay(afterAttempt: 2) == 10)
        #expect(StoredOutboxRepository.delay(afterAttempt: 3) == 20)
        #expect(StoredOutboxRepository.delay(afterAttempt: 40) == StoredOutboxRepository.maxDelay)
    }

    // MARK: - Removal

    @Test func acknowledgementIsTheOnlyThingThatRemovesAnEntry() throws {
        let repository = try makeRepository()
        let mutation = makeMutation()
        try repository.enqueue(mutation, at: .distantPast)

        try repository.recordFailure(of: mutation.id, error: .serverRejected, at: Date())
        #expect(try repository.entries().count == 1)

        try repository.acknowledge(id: mutation.id)
        #expect(try repository.entries().isEmpty)
    }

    @Test func entriesComeBackOldestFirst() throws {
        let repository = try makeRepository()
        let old = makeMutation(name: "first")
        let new = makeMutation(name: "second")
        try repository.enqueue(old, at: Date(timeIntervalSince1970: 100))
        try repository.enqueue(new, at: Date(timeIntervalSince1970: 200))

        #expect(try repository.entries().map(\.name) == ["first", "second"])
    }

    // MARK: - Fixtures

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: SwiftDataWardrobeItemRepository.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func makeRepository() throws -> StoredOutboxRepository {
        try StoredOutboxRepository(store: SwiftDataOutboxStore(context: makeContext()))
    }

    private func makeMutation(name: String = "upsertItem") -> OutboxMutation {
        OutboxMutation(name: name, payload: Data("{}".utf8))
    }

    private func makeEnvelope(id: UUID = UUID(), name: String = "upsertItem") -> OutboxEnvelope {
        OutboxEnvelope(
            id: id, name: name, payload: Data("{}".utf8),
            createdAt: Date(), nextAttemptAt: Date()
        )
    }

    private func makeItem() -> WardrobeItem {
        WardrobeItem(
            id: UUID(), name: "Shirt", description: "", category: .top, status: .pending,
            cutoutFile: "a.png", illustrationURL: nil, styleVersion: nil,
            createdAt: Date(), updatedAt: Date()
        )
    }
}
