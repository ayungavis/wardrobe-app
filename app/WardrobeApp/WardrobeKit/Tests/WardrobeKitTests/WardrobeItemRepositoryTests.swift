import Foundation
import SwiftData
import Testing
@testable import WardrobeKit

@MainActor
struct WardrobeItemRepositoryTests {
    private func makeSUT() throws -> SwiftDataWardrobeItemRepository {
        let container = try ModelContainer(
            for: SwiftDataWardrobeItemRepository.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return SwiftDataWardrobeItemRepository(container: container)
    }

    private func makeItem(
        id: UUID = UUID(),
        category: GarmentCategory = .top,
        createdAt: Date = Date()
    ) -> WardrobeItem {
        WardrobeItem(
            id: id,
            category: category,
            cutoutFile: "\(id.uuidString).png",
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }

    private func makeFingerprint(itemID: UUID) -> ItemFingerprint {
        ItemFingerprint(
            itemID: itemID,
            version: "v1+vision5",
            colorLab: [72.5, -3.25, 18],
            aspectRatio: 0.75,
            featurePrint: Data([0x00, 0xFF, 0x10, 0x42]),
            maskQuality: 0.82,
            createdAt: Date()
        )
    }

    @Test func insertedItemComesBackIdentical() throws {
        let sut = try makeSUT()
        let item = makeItem()

        try sut.insert(item, fingerprint: nil, wear: WearRecord(itemID: item.id, wornAt: item.createdAt))

        #expect(try sut.items() == [item])
    }

    @Test func itemsAreNewestFirst() throws {
        let sut = try makeSUT()
        let older = makeItem(createdAt: Date(timeIntervalSince1970: 1000))
        let newer = makeItem(createdAt: Date(timeIntervalSince1970: 2000))

        for item in [older, newer] {
            try sut.insert(item, fingerprint: nil, wear: WearRecord(itemID: item.id, wornAt: item.createdAt))
        }

        #expect(try sut.items().map(\.id) == [newer.id, older.id])
    }

    /// The blob is the piece most likely to be silently mangled by a storage
    /// layer, and a corrupted vector would quietly ruin every future match.
    @Test func fingerprintBlobAndColorsSurviveTheRoundTrip() throws {
        let sut = try makeSUT()
        let item = makeItem()
        let fingerprint = makeFingerprint(itemID: item.id)

        try sut.insert(item, fingerprint: fingerprint, wear: WearRecord(itemID: item.id, wornAt: Date()))

        let stored = try #require(sut.fingerprints().first)
        #expect(stored == fingerprint)
        #expect(stored.featurePrint == Data([0x00, 0xFF, 0x10, 0x42]))
        #expect(stored.colorLab == [72.5, -3.25, 18])
    }

    @Test func wearsAreScopedToTheirItem() throws {
        let sut = try makeSUT()
        let mine = makeItem()
        let other = makeItem()
        let myWear = WearRecord(itemID: mine.id, completionID: UUID(), wornAt: Date())

        try sut.insert(mine, fingerprint: nil, wear: myWear)
        try sut.insert(other, fingerprint: nil, wear: WearRecord(itemID: other.id, wornAt: Date()))

        #expect(try sut.wears(for: mine.id) == [myWear])
    }

    @Test func deleteAllEmptiesEveryTable() throws {
        let sut = try makeSUT()
        let item = makeItem()
        try sut.insert(item, fingerprint: makeFingerprint(itemID: item.id), wear: WearRecord(itemID: item.id, wornAt: Date()))

        try sut.deleteAll()

        #expect(try sut.items().isEmpty)
        #expect(try sut.fingerprints().isEmpty)
        #expect(try sut.wears(for: item.id).isEmpty)
    }

    @Test func insertWithoutFingerprintStillStoresItemAndWear() throws {
        let sut = try makeSUT()
        let item = makeItem()

        try sut.insert(item, fingerprint: nil, wear: WearRecord(itemID: item.id, wornAt: Date()))

        #expect(try sut.items().count == 1)
        #expect(try sut.fingerprints().isEmpty)
        #expect(try sut.wears(for: item.id).count == 1)
    }

    /// Screens reach storage through their own repository handle. A write made
    /// on one must be visible to the next read on another, or a rename made in
    /// the detail screen never reaches the wardrobe list.
    @Test func aWriteOnOneHandleIsVisibleToAnother() throws {
        let container = try ModelContainer(
            for: SwiftDataWardrobeItemRepository.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let writer = SwiftDataWardrobeItemRepository(container: container)
        let reader = SwiftDataWardrobeItemRepository(container: container)
        let item = makeItem()
        try writer.insert(item, fingerprint: nil, wear: WearRecord(itemID: item.id, wornAt: Date()))
        _ = try reader.items()

        var renamed = item
        renamed.name = "sleeve"
        try writer.update(renamed)

        #expect(try reader.items().first?.name == "sleeve")
    }
}
