import Foundation
import SwiftData
import Testing
@testable import WardrobeKit

@MainActor
struct ConflictResolutionTests {
    // MARK: - The counting rule (FR-065)

    @Test func wearsOfANonCanonicalCompletionAreNotCounted() throws {
        let sut = try makeSUT()
        let canonical = makeCompletion(status: .canonical)
        let conflicting = makeCompletion(status: .conflicting)
        sut.completions.append(canonical)
        sut.completions.append(conflicting)
        try sut.wardrobe.insert(
            makeItem(),
            fingerprint: nil,
            wear: WearRecord(itemID: itemID, completionID: canonical.id, wornAt: Date())
        )
        try sut.wardrobe.recordWear(
            WearRecord(itemID: itemID, completionID: conflicting.id, wornAt: Date()),
            fingerprint: makeFingerprint()
        )

        let counted = try sut.wardrobe.wears(for: itemID)

        #expect(counted.count == 1, "a conflicting completion's wear must not be counted")
        #expect(counted.first?.completionID == canonical.id)
    }

    @Test func aWearWithoutALocalCompletionStillCounts() throws {
        let sut = try makeSUT()
        try sut.wardrobe.insert(
            makeItem(),
            fingerprint: nil,
            wear: WearRecord(itemID: itemID, completionID: UUID(), wornAt: Date())
        )

        #expect(try sut.wardrobe.wears(for: itemID).count == 1)
    }

    @Test func bothPhotosSurviveAnUnresolvedConflict() throws {
        let sut = try makeSUT()
        let first = makeCompletion(status: .canonical)
        let second = makeCompletion(status: .conflicting)
        sut.completions.append(first)
        sut.completions.append(second)

        let stored = sut.completions.load()
        #expect(stored.count == 2)
        #expect(Set(stored.map(\.photoID)) == Set([first.photoID, second.photoID]))
    }

    // MARK: - Item conflict rows

    @Test func duplicateConflictRowsAreDeduplicated() throws {
        let sut = try makeSUT()
        try sut.wardrobe.stageApply(conflict: makeConflict(id: UUID()))
        try sut.wardrobe.stageApply(conflict: makeConflict(id: UUID()))
        try sut.wardrobe.commitStaged()

        #expect(try sut.wardrobe.openConflicts().count == 1,
                "replayed upserts insert duplicate rows server-side; the client de-dupes")
    }

    @Test func aStaleConflictArrivesAlreadyResolved() throws {
        let sut = try makeSUT()
        var item = makeItem()
        try sut.wardrobe.insert(item, fingerprint: nil, wear: nil)
        item.name = "renamed"
        try sut.wardrobe.update(item)

        try sut.wardrobe.stageApply(conflict: makeConflict(id: UUID(), revision: 0))
        try sut.wardrobe.commitStaged()

        #expect(try sut.wardrobe.openConflicts().isEmpty,
                "a conflict older than the field's local rev is already decided")
    }

    @Test func keepingTheCurrentValueWritesNoMutation() throws {
        let sut = try makeSUT()
        try sut.wardrobe.insert(makeItem(), fingerprint: nil, wear: nil)
        let conflict = makeConflict(id: UUID())
        try sut.wardrobe.stageApply(conflict: conflict)
        try sut.wardrobe.commitStaged()

        try sut.wardrobe.resolveConflict(conflict, choosing: .keepCurrent)

        #expect(try sut.wardrobe.openConflicts().isEmpty)
        #expect(try sut.outbox.entries().isEmpty, "the stored value already won; nothing to send")
    }

    @Test func usingTheIncomingValueEnqueuesOneSingleFieldUpsert() throws {
        let sut = try makeSUT()
        try sut.wardrobe.insert(makeItem(), fingerprint: nil, wear: nil)
        let conflict = makeConflict(id: UUID())
        try sut.wardrobe.stageApply(conflict: conflict)
        try sut.wardrobe.commitStaged()

        try sut.wardrobe.resolveConflict(conflict, choosing: .useIncoming)

        let entries = try sut.outbox.entries()
        #expect(entries.count == 1)
        #expect(entries.first?.name == "upsertItem")
        let payload = try #require(entries.first?.payload)
        let json = try #require(try JSONSerialization.jsonObject(with: payload) as? [String: Any])
        #expect(json["name"] != nil)
        #expect(json["category"] == nil && json["color"] == nil && json["description"] == nil)
        let field = try #require(json["name"] as? [String: Any])
        #expect(field["value"] as? String == "other")
        #expect(field["rev"] as? Int64 == conflict.revision + 1)
        #expect(try sut.wardrobe.items().first?.name == "other")
        #expect(try sut.wardrobe.openConflicts().isEmpty)
    }

    // MARK: - Choosing a completion

    @Test func choosingAWinnerDemotesTheOthersAndEnqueuesResolve() throws {
        let sut = try makeSUT()
        let winner = makeCompletion(status: .conflicting)
        let loser = makeCompletion(status: .canonical)
        sut.completions.append(winner)
        sut.completions.append(loser)

        let viewModel = makeViewModel(sut)
        viewModel.load()
        try viewModel.choose(winner)

        let byID = Dictionary(uniqueKeysWithValues: sut.completions.load().map { ($0.id, $0) })
        #expect(byID[winner.id]?.status == .canonical)
        #expect(byID[loser.id]?.status == .superseded)
        let entries = try sut.outbox.entries()
        #expect(entries.count == 1)
        #expect(entries.first?.name == "resolveCompletion")
    }

    @Test func choosingTwiceIsANoOp() throws {
        let sut = try makeSUT()
        let winner = makeCompletion(status: .conflicting)
        let loser = makeCompletion(status: .canonical)
        sut.completions.append(winner)
        sut.completions.append(loser)

        let viewModel = makeViewModel(sut)
        viewModel.load()
        try viewModel.choose(winner)
        try viewModel.choose(winner)

        #expect(try sut.outbox.entries().count == 1,
                "an already-canonical winner with no contenders must enqueue nothing")
    }

    @Test func resolutionCountsTheWinnersWearsExactlyOnce() throws {
        let sut = try makeSUT()
        let winner = makeCompletion(status: .conflicting)
        let loser = makeCompletion(status: .canonical)
        sut.completions.append(winner)
        sut.completions.append(loser)
        try sut.wardrobe.insert(
            makeItem(),
            fingerprint: nil,
            wear: WearRecord(itemID: itemID, completionID: winner.id, wornAt: Date())
        )
        try sut.wardrobe.recordWear(
            WearRecord(itemID: itemID, completionID: loser.id, wornAt: Date()),
            fingerprint: makeFingerprint()
        )

        let viewModel = makeViewModel(sut)
        viewModel.load()
        try viewModel.choose(winner)
        try viewModel.choose(winner)

        let counted = try sut.wardrobe.wears(for: itemID)
        #expect(counted.count == 1)
        #expect(counted.first?.completionID == winner.id)
    }

    // MARK: - Fixtures

    private let itemID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, 0x1A))

    private struct SUT {
        let wardrobe: SwiftDataWardrobeItemRepository
        let completions: SwiftDataCompletedChallengeRepository
        let outbox: StoredOutboxRepository
    }

    private func makeSUT() throws -> SUT {
        let container = try ModelContainer(
            for: SwiftDataWardrobeItemRepository.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let outbox = StoredOutboxRepository(store: SwiftDataOutboxStore(context: context))
        return SUT(
            wardrobe: SwiftDataWardrobeItemRepository(context: context, outbox: outbox),
            completions: SwiftDataCompletedChallengeRepository(context: context),
            outbox: outbox
        )
    }

    private func makeViewModel(_ sut: SUT) -> ConflictsViewModel {
        ConflictsViewModel(wardrobe: sut.wardrobe, completions: sut.completions, outbox: sut.outbox)
    }

    private func makeItem() -> WardrobeItem {
        WardrobeItem(
            id: itemID, name: "coat", description: "", category: .top,
            cutoutFile: "", createdAt: Date(), updatedAt: Date()
        )
    }

    private func makeFingerprint() -> ItemFingerprint {
        ItemFingerprint(
            id: UUID(), itemID: itemID, version: "v1", colorLab: [1, 2, 3],
            aspectRatio: 1, featurePrint: Data(), maskQuality: 1, createdAt: Date()
        )
    }

    private func makeConflict(id: UUID, revision: Int64 = 5) -> ItemConflict {
        ItemConflict(id: id, itemID: itemID, field: .name, value: "other", revision: revision)
    }

    private func makeCompletion(status: CompletionStatus) -> CompletedChallenge {
        var completion = CompletedChallenge(
            card: ChallengeCard(id: UUID(), prompt: "p"),
            photoID: UUID(),
            document: EditorDocument(id: UUID(), layers: []),
            completedAt: Date()
        )
        completion.status = status
        return completion
    }
}
