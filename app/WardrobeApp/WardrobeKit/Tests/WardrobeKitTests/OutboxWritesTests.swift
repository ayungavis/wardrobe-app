import Foundation
import SwiftData
import Testing
@testable import WardrobeKit

@MainActor
struct OutboxWritesTests {
    // MARK: - Deletion leaves a tombstone

    @Test func aDeletedItemLeavesATombstoneRatherThanAnAbsence() throws {
        let context = try makeContext()
        let repository = SwiftDataWardrobeItemRepository(context: context)
        let item = makeItem()
        try repository.insert(item, fingerprint: nil, wear: nil)

        try repository.delete(itemID: item.id)

        #expect(try repository.items().isEmpty)
        let rows = try context.fetch(FetchDescriptor<WardrobeItemEntity>())
        #expect(rows.count == 1)
        #expect(rows.first?.deletedAt != nil)
    }

    @Test func deletingEnqueuesExactlyOneDeleteItem() throws {
        let (repository, outbox) = try makeSUT()
        let item = makeItem()
        try repository.insert(item, fingerprint: nil, wear: nil)

        try repository.delete(itemID: item.id)

        let entries = try outbox.entries()
        #expect(entries.count == 1)
        #expect(entries.first?.name == "deleteItem")
    }

    @Test func deletingTwiceEnqueuesOnlyOnce() throws {
        let (repository, outbox) = try makeSUT()
        let item = makeItem()
        try repository.insert(item, fingerprint: nil, wear: nil)

        try repository.delete(itemID: item.id)
        try repository.delete(itemID: item.id)

        #expect(try outbox.entries().count == 1)
    }

    @Test func aBuriedItemStopsOfferingItsFingerprintToTheMatcher() throws {
        let (repository, _) = try makeSUT()
        let item = makeItem()
        try repository.insert(item, fingerprint: makeFingerprint(itemID: item.id), wear: nil)
        #expect(try repository.fingerprints().count == 1)

        try repository.delete(itemID: item.id)

        #expect(try repository.fingerprints().isEmpty)
    }

    // MARK: - Editing

    @Test func onlyTheChangedFieldIsSent() throws {
        let (repository, outbox) = try makeSUT()
        var item = makeItem()
        try repository.insert(item, fingerprint: nil, wear: nil)

        item.name = "storm coat"
        try repository.update(item)

        let entry = try #require(try outbox.entries().first)
        let payload = try #require(String(bytes: entry.payload, encoding: .utf8))
        #expect(entry.name == "upsertItem")
        #expect(payload.contains("storm coat"))
        #expect(!payload.contains("category"))
        #expect(!payload.contains("description"))
    }

    @Test func anEditThatChangesNothingQueuesNothing() throws {
        let (repository, outbox) = try makeSUT()
        let item = makeItem()
        try repository.insert(item, fingerprint: nil, wear: nil)

        try repository.update(item)

        #expect(try outbox.entries().isEmpty)
    }

    @Test func eachEditRaisesOnlyItsOwnFieldRevision() throws {
        let (repository, outbox) = try makeSUT()
        var item = makeItem()
        try repository.insert(item, fingerprint: nil, wear: nil)

        item.name = "first"
        try repository.update(item)
        item.name = "second"
        try repository.update(item)

        let payloads = try outbox.entries().compactMap { String(bytes: $0.payload, encoding: .utf8) }
        #expect(payloads.count == 2)
        #expect(payloads[0].contains("\"rev\":1"))
        #expect(payloads[1].contains("\"rev\":2"))
    }

    // MARK: - One transaction

    @Test func aRolledBackEditLeavesNeitherTheChangeNorTheEntry() throws {
        let context = try makeContext()
        let outbox = StoredOutboxRepository(store: SwiftDataOutboxStore(context: context))
        let repository = SwiftDataWardrobeItemRepository(context: context, outbox: outbox)
        var item = makeItem()
        try repository.insert(item, fingerprint: nil, wear: nil)

        item.name = "never committed"
        let entity = try #require(try context.fetch(FetchDescriptor<WardrobeItemEntity>()).first)
        entity.name = item.name
        try outbox.stage(SyncMutation.upsertItem(UpsertItemArgsDTO(id: item.id)).queued(), at: Date())
        context.rollback()

        #expect(try outbox.entries().isEmpty)
        #expect(try repository.items().first?.name != "never committed")
    }

    // MARK: - Preferences

    @Test func aSyncablePreferenceChangeQueuesOneEntry() throws {
        let (outbox, preferences) = try makePreferences("prefs.syncable")

        preferences.save(AccountPreferences(recentStickerIDs: ["emoji.fire"]))

        let entries = try outbox.entries()
        #expect(entries.count == 1)
        #expect(entries.first?.name == "upsertPreferences")
    }

    @Test func aDeviceOnlyPreferenceChangeQueuesNothing() throws {
        let (outbox, preferences) = try makePreferences("prefs.deviceOnly")

        preferences.save(AccountPreferences(hasSeenCaptureTips: true))

        #expect(try outbox.entries().isEmpty)
    }

    @Test func repeatedStickerWritesCollapseIntoOneEntry() throws {
        let (outbox, preferences) = try makePreferences("prefs.collapse")

        preferences.save(AccountPreferences(recentStickerIDs: ["a"]))
        preferences.save(AccountPreferences(recentStickerIDs: ["b", "a"]))
        preferences.save(AccountPreferences(recentStickerIDs: ["c", "b", "a"]))

        let entries = try outbox.entries()
        #expect(entries.count == 1)
        let payload = try #require(String(bytes: entries[0].payload, encoding: .utf8))
        #expect(payload.contains("\"c\""))
    }

    // MARK: - Save and Share cannot reach the outbox

    @Test func theEditorNeverReferencesTheOutbox() throws {
        let editor = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Sources/WardrobeKit/Features/Editor")
        let forbidden = ["OutboxRepository", "SyncMutation", "outbox"]

        var offenders: [String] = []
        let files = FileManager.default.enumerator(at: editor, includingPropertiesForKeys: nil)
        while let url = files?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            let source = try String(contentsOf: url, encoding: .utf8)
            for word in forbidden where source.contains(word) {
                offenders.append("\(url.lastPathComponent): \(word)")
            }
        }

        #expect(offenders.isEmpty, "FR-028/FR-094: only the checkmark completes")
    }

    // MARK: - Fixtures

    private func makeSUT() throws -> (SwiftDataWardrobeItemRepository, StoredOutboxRepository) {
        let context = try makeContext()
        let outbox = StoredOutboxRepository(store: SwiftDataOutboxStore(context: context))
        return (SwiftDataWardrobeItemRepository(context: context, outbox: outbox), outbox)
    }

    private func makePreferences(
        _ suite: String
    ) throws -> (StoredOutboxRepository, UserDefaultsAccountPreferencesRepository) {
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let outbox = StoredOutboxRepository(store: InMemoryOutboxStore())
        return (outbox, UserDefaultsAccountPreferencesRepository(defaults: defaults, outbox: outbox))
    }

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: SwiftDataWardrobeItemRepository.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func makeFingerprint(itemID: UUID) -> ItemFingerprint {
        ItemFingerprint(
            itemID: itemID, version: "v1+vision5", colorLab: [72.5, -3.25, 18],
            aspectRatio: 0.75, featurePrint: Data([0x00, 0xFF]), maskQuality: 0.82, createdAt: Date()
        )
    }

    private func makeItem(id: UUID = UUID()) -> WardrobeItem {
        WardrobeItem(id: id, category: .top, cutoutFile: "\(id.uuidString).png",
                     createdAt: Date(), updatedAt: Date())
    }
}
