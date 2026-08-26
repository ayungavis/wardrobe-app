import Foundation
import Testing
@testable import WardrobeKit

@MainActor
struct WardrobeItemDetailViewModelTests {
    @Test func theRegenerateSheetCanShowWhatTheItemReallyLooksLike() async throws {
        let repository = InMemoryWardrobeItemRepository()
        let thumbnails = InMemoryGarmentThumbnailRepository()
        let photos = SpyPhotoRepository()
        let completions = InMemoryCompletedChallengeRepository()

        let cutout = try SampleCameraService.makeSampleJPEG(width: 40, height: 40)
        thumbnails.files["cut.png"] = cutout
        let original = try SampleCameraService.makeSampleJPEG(width: 80, height: 120)
        let photoID = try photos.saveOriginal(original)
        let completion = CompletedChallenge(
            card: ChallengeCard(id: UUID(), prompt: "p"),
            photoID: photoID,
            document: EditorDocument(id: UUID(), layers: []),
            completedAt: Date()
        )
        completions.append(completion)

        let item = WardrobeItem(category: .top, cutoutFile: "cut.png",
                                createdAt: Date(), updatedAt: Date())
        try repository.insert(
            item,
            fingerprint: nil,
            wear: WearRecord(itemID: item.id, completionID: completion.id, wornAt: Date())
        )

        let sut = WardrobeItemDetailViewModel(
            itemID: item.id,
            repository: repository,
            thumbnails: thumbnails,
            completions: completions,
            photos: photos
        )
        sut.load()
        await sut.loadTask?.value

        #expect(sut.cutoutData() == cutout)
        #expect(sut.originalPhotoData() == original,
                "asking for a better drawing is easier when you can see what it is drawing")
    }

    @Test func askingForANewIllustrationPushesItStraightAway() async throws {
        let repository = InMemoryWardrobeItemRepository()
        let item = WardrobeItem(category: .top, cutoutFile: "a.png",
                                createdAt: Date(), updatedAt: Date())
        try repository.insert(item, fingerprint: nil, wear: nil)
        let pushes = Pushes()
        let sut = WardrobeItemDetailViewModel(
            itemID: item.id,
            repository: repository,
            thumbnails: InMemoryGarmentThumbnailRepository(),
            syncNow: { await pushes.record() }
        )
        sut.load()
        await sut.loadTask?.value

        sut.regenerateIllustration(note: "shorts")
        await sut.syncTask?.value

        #expect(await pushes.count == 1,
                "a queue nobody drains until the next tab switch feels broken to the person waiting")
    }

    private let version = "v1+vision2"

    private func makeSUT(
        itemID: UUID,
        repository: InMemoryWardrobeItemRepository,
        thumbnails: InMemoryGarmentThumbnailRepository = InMemoryGarmentThumbnailRepository()
    ) -> WardrobeItemDetailViewModel {
        WardrobeItemDetailViewModel(itemID: itemID, repository: repository, thumbnails: thumbnails)
    }

    @discardableResult
    private func makeItem(
        in repository: InMemoryWardrobeItemRepository,
        category: GarmentCategory = .top,
        color: [Float] = [70, 5, 15],
        print vector: [Float] = [1, 0, 0, 0],
        wornAt dates: [Date] = []
    ) -> WardrobeItem {
        let id = UUID()
        let item = WardrobeItem(
            id: id, category: category, cutoutFile: "\(id.uuidString).png",
            createdAt: Date(), updatedAt: Date()
        )
        repository.storedItems.append(item)
        repository.storedFingerprints.append(makeFingerprint(itemID: id, color: color, print: vector))
        for date in dates {
            repository.storedWears.append(WearRecord(itemID: id, wornAt: date))
        }
        return item
    }

    private func makeFingerprint(itemID: UUID, color: [Float], print vector: [Float]) -> ItemFingerprint {
        ItemFingerprint(
            itemID: itemID,
            version: version,
            colorLab: color,
            aspectRatio: 0.8,
            featurePrint: vector.withUnsafeBufferPointer { Data(buffer: $0) },
            maskQuality: 1,
            createdAt: Date()
        )
    }

    private func date(_ day: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + Double(day) * 86400)
    }

    // MARK: Usage summary

    /// Deliberately unsorted input: the summary computes its own extremes rather
    /// than trusting whatever order a repository happens to return.
    @Test func usageIsDerivedFromTheWearRecords() async {
        let repository = InMemoryWardrobeItemRepository()
        let item = makeItem(in: repository, wornAt: [date(3), date(1), date(7)])
        let sut = makeSUT(itemID: item.id, repository: repository)

        sut.load()

        await sut.loadTask?.value

        #expect(sut.wearCount == 3)
        #expect(sut.firstWornAt == date(1))
        #expect(sut.lastWornAt == date(7))
    }

    /// FR-023: missing history is stated, never filled with an invented date.
    @Test func anItemNeverWornHasNoDates() async {
        let repository = InMemoryWardrobeItemRepository()
        let item = makeItem(in: repository)
        let sut = makeSUT(itemID: item.id, repository: repository)

        sut.load()

        await sut.loadTask?.value

        #expect(sut.wearCount == 0)
        #expect(sut.firstWornAt == nil)
        #expect(sut.lastWornAt == nil)
    }

    // MARK: Similar items

    @Test func aLookalikeInTheSameCategoryIsOffered() async {
        let repository = InMemoryWardrobeItemRepository()
        let item = makeItem(in: repository)
        let twin = makeItem(in: repository)
        let sut = makeSUT(itemID: item.id, repository: repository)

        sut.load()

        await sut.loadTask?.value

        #expect(sut.similar.map(\.item.id) == [twin.id])
    }

    /// The item is never its own lookalike, however identical its fingerprints.
    @Test func theItemIsNeverSimilarToItself() async {
        let repository = InMemoryWardrobeItemRepository()
        let item = makeItem(in: repository)
        let sut = makeSUT(itemID: item.id, repository: repository)

        sut.load()

        await sut.loadTask?.value

        #expect(sut.similar.isEmpty)
    }

    /// A top is never a bottom, which is the matcher's hard filter and must hold
    /// here too rather than being re-decided per screen.
    @Test func similarityNeverCrossesCategories() async {
        let repository = InMemoryWardrobeItemRepository()
        let item = makeItem(in: repository, category: .top)
        makeItem(in: repository, category: .bottom)
        let sut = makeSUT(itemID: item.id, repository: repository)

        sut.load()

        await sut.loadTask?.value

        #expect(sut.similar.isEmpty)
    }

    @Test func aVeryDifferentGarmentIsNotOffered() async {
        let repository = InMemoryWardrobeItemRepository()
        let item = makeItem(in: repository, color: [70, 5, 15], print: [1, 0, 0, 0])
        makeItem(in: repository, color: [20, -30, -30], print: [0, 1, 0, 0])
        let sut = makeSUT(itemID: item.id, repository: repository)

        sut.load()

        await sut.loadTask?.value

        #expect(sut.similar.isEmpty)
    }

    // MARK: Deleting

    @Test func deletingRemovesTheItemItsHistoryAndItsImage() async {
        let repository = InMemoryWardrobeItemRepository()
        let thumbnails = InMemoryGarmentThumbnailRepository()
        let item = makeItem(in: repository, wornAt: [date(1), date(2)])
        thumbnails.files[item.cutoutFile] = Data([0x01])
        let sut = makeSUT(itemID: item.id, repository: repository, thumbnails: thumbnails)
        sut.load()
        await sut.loadTask?.value

        sut.delete()

        #expect(sut.isDeleted)
        #expect(repository.storedItems.isEmpty)
        #expect(repository.storedFingerprints.isEmpty)
        #expect(repository.storedWears.isEmpty)
        #expect(thumbnails.files.isEmpty)
    }

    /// A cut-out that already vanished must not strand the row that points at
    /// it — that is exactly how an undeletable item would be born.
    @Test func deletingSucceedsWhenTheImageIsAlreadyGone() async {
        let repository = InMemoryWardrobeItemRepository()
        let item = makeItem(in: repository)
        let sut = makeSUT(itemID: item.id, repository: repository)
        sut.load()
        await sut.loadTask?.value

        sut.delete()

        #expect(sut.isDeleted)
        #expect(repository.storedItems.isEmpty)
    }

    @Test func deletingLeavesEveryOtherItemAlone() async {
        let repository = InMemoryWardrobeItemRepository()
        let item = makeItem(in: repository, wornAt: [date(1)])
        let survivor = makeItem(in: repository, color: [20, -30, -30], print: [0, 1, 0, 0],
                                wornAt: [date(2), date(3)])
        let sut = makeSUT(itemID: item.id, repository: repository)
        sut.load()
        await sut.loadTask?.value

        sut.delete()

        #expect(repository.storedItems.map(\.id) == [survivor.id])
        #expect(repository.storedWears.count == 2)
        #expect(repository.storedFingerprints.count == 1)
    }
}

actor Pushes {
    private(set) var count = 0

    func record() {
        count += 1
    }
}
