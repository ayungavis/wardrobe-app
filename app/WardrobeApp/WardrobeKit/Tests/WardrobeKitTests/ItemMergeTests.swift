import Foundation
import SwiftData
import Testing
@testable import WardrobeKit

@MainActor
struct ItemMergeTests {
    @Test func aMergeStagesExactlyOneMergeItemsMutation() throws {
        let sut = try makeSUT()

        try sut.wardrobe.merge(winnerID: winnerID, loserID: loserID)

        let names = try sut.outbox.entries().map(\.name)
        #expect(names == ["mergeItems"], "a merge is one mutation; deleteItem would double-tombstone")
    }

    @Test func wearsAndFingerprintsMoveToTheSurvivor() throws {
        let sut = try makeSUT()

        try sut.wardrobe.merge(winnerID: winnerID, loserID: loserID)

        let moved = try sut.wardrobe.wears(for: winnerID)
        #expect(moved.count == 2, "the loser's wear joins the winner's")
        #expect(Set(moved.map(\.id)).count == 2, "moved, never duplicated")
        #expect(try sut.wardrobe.wears(for: loserID).isEmpty)
        #expect(try sut.wardrobe.fingerprints().allSatisfy { $0.itemID == winnerID })
    }

    @Test func theLoserIsTombstonedNotDeleted() throws {
        let sut = try makeSUT()

        try sut.wardrobe.merge(winnerID: winnerID, loserID: loserID)

        #expect(try sut.wardrobe.items().map(\.id) == [winnerID])
        try sut.wardrobe.merge(winnerID: winnerID, loserID: loserID)
        #expect(try sut.outbox.entries().count == 1,
                "a second merge of a buried loser is a no-op, proving the tombstone row survives")
    }

    @Test func theLosersOpenConflictsClose() throws {
        let sut = try makeSUT()
        try sut.wardrobe.stageApply(conflict: ItemConflict(
            id: UUID(), itemID: loserID, field: .name, value: "other", revision: 5
        ))
        try sut.wardrobe.commitStaged()

        try sut.wardrobe.merge(winnerID: winnerID, loserID: loserID)

        #expect(try sut.wardrobe.openConflicts().isEmpty)
    }

    @Test func nothingMergesWithoutExplicitConfirmation() throws {
        let sut = try makeSUT()
        let viewModel = WardrobeItemDetailViewModel(
            itemID: winnerID,
            repository: sut.wardrobe,
            thumbnails: InMemoryGarmentThumbnailRepository()
        )
        viewModel.load()
        let entry = try SimilarItem(
            item: #require(try sut.wardrobe.items().first { $0.id == loserID }),
            match: ItemMatch(itemID: loserID, score: 0.9, confidence: .likely)
        )

        viewModel.requestMerge(entry)

        #expect(try sut.wardrobe.items().count == 2, "asking is not merging (FR-026)")
        #expect(try sut.outbox.entries().isEmpty)

        viewModel.confirmMerge()

        #expect(try sut.wardrobe.items().map(\.id) == [winnerID])
        #expect(try sut.outbox.entries().map(\.name) == ["mergeItems"])
    }

    // MARK: - Fixtures

    private let winnerID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, 0x3A))
    private let loserID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, 0x3B))

    private struct SUT {
        let wardrobe: SwiftDataWardrobeItemRepository
        let outbox: StoredOutboxRepository
    }

    private func makeSUT() throws -> SUT {
        let container = try ModelContainer(
            for: SwiftDataWardrobeItemRepository.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let outbox = StoredOutboxRepository(store: SwiftDataOutboxStore(context: context))
        let wardrobe = SwiftDataWardrobeItemRepository(context: context, outbox: outbox)
        try wardrobe.insert(
            makeItem(id: winnerID, name: "coat"),
            fingerprint: makeFingerprint(itemID: winnerID),
            wear: WearRecord(itemID: winnerID, wornAt: Date())
        )
        try wardrobe.insert(
            makeItem(id: loserID, name: "same coat"),
            fingerprint: makeFingerprint(itemID: loserID),
            wear: WearRecord(itemID: loserID, wornAt: Date())
        )
        return SUT(wardrobe: wardrobe, outbox: outbox)
    }

    private func makeItem(id: UUID, name: String) -> WardrobeItem {
        WardrobeItem(
            id: id, name: name, description: "", category: .top,
            cutoutFile: "", createdAt: Date(), updatedAt: Date()
        )
    }

    private func makeFingerprint(itemID: UUID) -> ItemFingerprint {
        ItemFingerprint(
            id: UUID(), itemID: itemID, version: "v1", colorLab: [1, 2, 3],
            aspectRatio: 1, featurePrint: Data(), maskQuality: 1, createdAt: Date()
        )
    }
}
