import CoreGraphics
import Foundation
import Testing
@testable import WardrobeKit

@MainActor
struct GarmentReviewModelTests {
    private func makeSUT(
        repository: InMemoryWardrobeItemRepository = InMemoryWardrobeItemRepository(),
        thumbnails: InMemoryGarmentThumbnailRepository = InMemoryGarmentThumbnailRepository(),
        scanner: FakeGarmentScanService = FakeGarmentScanService()
    ) -> GarmentReviewModel {
        GarmentReviewModel(
            scanner: scanner, photoRepository: SpyPhotoRepository(),
            wardrobeRepository: repository, thumbnails: thumbnails
        )
    }

    private func makeGarment(
        decision: ScannedGarment.Decision,
        matches: [ItemMatch] = [],
        file: String = "\(UUID().uuidString).png"
    ) -> ScannedGarment {
        let id = UUID()
        return ScannedGarment(
            id: id,
            category: .top,
            cutoutFile: file,
            fingerprint: ItemFingerprint(
                itemID: id, version: "v1", colorLab: [70, 5, 15], aspectRatio: 0.8,
                featurePrint: Data([1, 2, 3, 4]), maskQuality: 1, createdAt: Date()
            ),
            matches: matches,
            decision: decision
        )
    }

    private func makeExistingItem(in repository: InMemoryWardrobeItemRepository) throws -> WardrobeItem {
        let id = UUID()
        let item = WardrobeItem(
            id: id, category: .top, cutoutFile: "\(id.uuidString).png",
            createdAt: Date(), updatedAt: Date()
        )
        try repository.insert(item, fingerprint: nil, wear: WearRecord(itemID: id, wornAt: Date()))
        return item
    }

    // MARK: Decision defaults

    @Test func aConfidentMatchIsPreSelectedAndAnUncertainOneIsNot() {
        let itemID = UUID()

        let likely = ScannedGarment.defaultDecision(
            for: [ItemMatch(itemID: itemID, score: 0.9, confidence: .likely)]
        )
        let uncertain = ScannedGarment.defaultDecision(
            for: [ItemMatch(itemID: itemID, score: 0.6, confidence: .uncertain)]
        )

        #expect(likely == .existing(itemID))
        #expect(uncertain == .new)
        #expect(ScannedGarment.defaultDecision(for: []) == .new)
    }

    // MARK: Confirming

    @Test func confirmingANewGarmentStoresItemFingerprintAndWear() throws {
        let repository = InMemoryWardrobeItemRepository()
        let sut = makeSUT(repository: repository)
        let garment = makeGarment(decision: .new)
        sut.stage([garment])

        sut.commit(completionID: nil, at: Date())

        #expect(try repository.items().map(\.id) == [garment.id])
        #expect(try repository.fingerprints().count == 1)
        #expect(try repository.wears(for: garment.id).count == 1)
        #expect(sut.garments.isEmpty)
    }

    /// The whole point of A7: a garment the user already owns must not become a
    /// second item.
    @Test func confirmingADuplicateAddsAWearInsteadOfAnItem() throws {
        let repository = InMemoryWardrobeItemRepository()
        let thumbnails = InMemoryGarmentThumbnailRepository()
        let existing = try makeExistingItem(in: repository)
        let sut = makeSUT(repository: repository, thumbnails: thumbnails)
        let garment = makeGarment(decision: .existing(existing.id), file: "scanned.png")
        thumbnails.files["scanned.png"] = Data([0x01])
        sut.stage([garment])

        sut.commit(completionID: nil, at: Date())

        #expect(try repository.items().count == 1)
        #expect(try repository.wears(for: existing.id).count == 2)
        // The new fingerprint is filed under the item it belongs to, so the next
        // match has more references to compare against.
        #expect(try repository.fingerprints().allSatisfy { $0.itemID == existing.id })
        #expect(thumbnails.files["scanned.png"] == nil)
    }

    @Test func cancellingWritesNothingAndCleansUpItsImages() throws {
        let repository = InMemoryWardrobeItemRepository()
        let thumbnails = InMemoryGarmentThumbnailRepository()
        thumbnails.files["scanned.png"] = Data([0x01])
        let sut = makeSUT(repository: repository, thumbnails: thumbnails)
        sut.stage([makeGarment(decision: .new, file: "scanned.png")])

        sut.cancel()

        #expect(try repository.items().isEmpty)
        #expect(thumbnails.files.isEmpty)
        #expect(sut.garments.isEmpty)
    }

    // MARK: Discarding

    /// A bag or a slice of background must leave no trace — least of all a
    /// fingerprint, which would poison every later match.
    @Test func discardingWritesNothingAndDeletesTheCutout() throws {
        let repository = InMemoryWardrobeItemRepository()
        let thumbnails = InMemoryGarmentThumbnailRepository()
        thumbnails.files["bogus.png"] = Data([0x01])
        let sut = makeSUT(repository: repository, thumbnails: thumbnails)
        sut.stage([makeGarment(decision: .discard, file: "bogus.png")])

        sut.commit(completionID: nil, at: Date())

        #expect(try repository.items().isEmpty)
        #expect(try repository.fingerprints().isEmpty)
        #expect(thumbnails.files.isEmpty)
        #expect(sut.garments.isEmpty)
    }

    @Test func discardingOneGarmentKeepsTheOthersInTheSameBatch() throws {
        let repository = InMemoryWardrobeItemRepository()
        let thumbnails = InMemoryGarmentThumbnailRepository()
        thumbnails.files["bogus.png"] = Data([0x01])
        thumbnails.files["shirt.png"] = Data([0x02])
        let sut = makeSUT(repository: repository, thumbnails: thumbnails)
        let kept = makeGarment(decision: .new, file: "shirt.png")
        sut.stage([makeGarment(decision: .discard, file: "bogus.png"), kept])

        sut.commit(completionID: nil, at: Date())

        #expect(try repository.items().map(\.id) == [kept.id])
        #expect(thumbnails.files.keys.sorted() == ["shirt.png"])
    }

    @Test func choosingOverridesTheProposal() {
        let sut = makeSUT()
        let itemID = UUID()
        let garment = makeGarment(
            decision: .existing(itemID),
            matches: [ItemMatch(itemID: itemID, score: 0.9, confidence: .likely)]
        )
        sut.stage([garment])

        sut.choose(.new, for: garment.id)

        #expect(sut.garments.first?.decision == .new)
    }

    @Test func choosingTouchesOnlyTheRowItNames() {
        let sut = makeSUT()
        let first = makeGarment(decision: .new)
        let second = makeGarment(decision: .new)
        sut.stage([first, second])

        sut.choose(.discard, for: second.id)

        #expect(sut.garments.first?.decision == .new)
        #expect(sut.garments.last?.decision == .discard)
    }
}
