import Foundation
import Testing
@testable import WardrobeKit

@MainActor
struct WearIdentityTests {
    private func garment(decision: ScannedGarment.Decision) -> ScannedGarment {
        let id = UUID()
        return ScannedGarment(
            id: id,
            category: .top,
            cutoutFile: "\(id.uuidString).png",
            fingerprint: ItemFingerprint(
                itemID: id, version: "v1", colorLab: [70, 5, 15], aspectRatio: 0.8,
                featurePrint: Data([1, 2, 3, 4]), maskQuality: 1, createdAt: Date()
            ),
            matches: [],
            decision: decision
        )
    }

    private func completion() -> CompletedChallenge {
        CompletedChallenge(
            card: ChallengeCard(prompt: "Wear red"),
            photoID: UUID(),
            document: EditorDocument(id: UUID(), layers: []),
            completedAt: Date()
        )
    }

    @Test func aWearKeepsOneIdentityFromReviewToSync() throws {
        let garments = [garment(decision: .new), garment(decision: .existing(UUID()))]

        let plan = try CompletionSyncPlanner.plan(
            for: completion(), items: garments, at: Date()
        )
        let sent = plan.args.items.map(\.wearId)

        #expect(
            sent == garments.map(\.wearID),
            "the planner minting its own id leaves the local wear and the server's wear as two  separate rows for one wearing"
        )
    }

    @Test func applyingTheSameWearTwiceKeepsOneRow() throws {
        let sut = try makeSUT()
        let wear = WearRecord(itemID: itemID, completionID: UUID(), wornAt: Date())

        try sut.repository.stageApply(wear: wear, deletedAt: nil)
        try sut.repository.stageApply(wear: wear, deletedAt: nil)
        try sut.repository.commitStaged()

        let wears = try sut.repository.wears(for: itemID).count
        #expect(
            wears == 1,
            "a cursor rewind replays records on purpose; an applier that always inserts turns that  into duplicated data"
        )
    }

    @Test func applyingAWearThatChangedUpdatesItInPlace() throws {
        let sut = try makeSUT()
        let id = UUID()
        let first = Date(timeIntervalSince1970: 1_787_000_000)
        let second = first.addingTimeInterval(86400)

        try sut.repository.stageApply(
            wear: WearRecord(id: id, itemID: itemID, completionID: nil, wornAt: first), deletedAt: nil
        )
        try sut.repository.stageApply(
            wear: WearRecord(id: id, itemID: itemID, completionID: nil, wornAt: second), deletedAt: nil
        )
        try sut.repository.commitStaged()

        let wears = try sut.repository.wears(for: itemID)
        #expect(wears.count == 1)
        #expect(wears.first?.wornAt == second)
    }
}
