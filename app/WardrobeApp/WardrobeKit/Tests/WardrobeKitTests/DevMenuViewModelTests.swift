import Foundation
import Testing
@testable import WardrobeKit

@MainActor
struct DevMenuViewModelTests {
    private func makeSUT(
        activeRepository: InMemoryActiveChallengeRepository = InMemoryActiveChallengeRepository(),
        completedRepository: InMemoryCompletedChallengeRepository = InMemoryCompletedChallengeRepository(),
        photoRepository: SpyPhotoRepository = SpyPhotoRepository(),
        wardrobeRepository: InMemoryWardrobeItemRepository = InMemoryWardrobeItemRepository(),
        thumbnails: InMemoryGarmentThumbnailRepository = InMemoryGarmentThumbnailRepository()
    ) -> DevMenuViewModel {
        DevMenuViewModel(
            activeRepository: activeRepository,
            completedRepository: completedRepository,
            photoRepository: photoRepository,
            wardrobeRepository: wardrobeRepository,
            thumbnails: thumbnails
        )
    }

    private func makeWardrobeItem() -> WardrobeItem {
        let id = UUID()
        return WardrobeItem(id: id, category: .top, cutoutFile: "\(id.uuidString).png",
                            createdAt: Date(), updatedAt: Date())
    }

    @Test func resetWardrobeClearsItemsAndTheirImages() throws {
        let wardrobe = InMemoryWardrobeItemRepository()
        let thumbnails = InMemoryGarmentThumbnailRepository()
        let item = makeWardrobeItem()
        try wardrobe.insert(item, fingerprint: nil, wear: WearRecord(itemID: item.id, wornAt: Date()))
        thumbnails.files[item.cutoutFile] = Data([0x01])
        let sut = makeSUT(wardrobeRepository: wardrobe, thumbnails: thumbnails)

        sut.resetWardrobe()

        #expect(try wardrobe.items().isEmpty)
        #expect(thumbnails.files.isEmpty)
        #expect(thumbnails.deleteAllCount == 1)
        #expect(sut.summary.wardrobeItemCount == 0)
        #expect(sut.lastAction != nil)
    }

    @Test func summaryCountsWardrobeItems() throws {
        let wardrobe = InMemoryWardrobeItemRepository()
        let item = makeWardrobeItem()
        try wardrobe.insert(item, fingerprint: nil, wear: WearRecord(itemID: item.id, wornAt: Date()))
        let sut = makeSUT(wardrobeRepository: wardrobe)

        sut.refresh()

        #expect(sut.summary.wardrobeItemCount == 1)
    }

    /// The document carries its own photo, distinct from the capture — that is
    /// the shape FR-093 produces, and the only one that can catch a leak.
    private func makeCompletion(
        at date: Date,
        photoID: String = UUID().uuidString,
        extraPhotoIDs: [String] = []
    ) -> CompletedChallenge {
        var document = EditorDocument.fixture(photoID: "doc-\(photoID)")
        for extra in extraPhotoIDs {
            document.appendPhoto(extra)
        }
        return CompletedChallenge(
            card: ChallengeCard(prompt: "x"),
            photoID: photoID,
            document: document,
            completedAt: date
        )
    }

    private func makeActive(photoID: String?) -> ActiveChallenge {
        var challenge = ActiveChallenge(card: ChallengeCard(prompt: "x"), acceptedAt: .distantPast)
        challenge.photoID = photoID
        return challenge
    }

    @Test func resetTodayClearsCompletionActiveChallengeAndPhotos() {
        let activeRepository = InMemoryActiveChallengeRepository()
        activeRepository.stored = makeActive(photoID: "active-photo")
        let completedRepository = InMemoryCompletedChallengeRepository()
        completedRepository.stored = [makeCompletion(at: Date(), photoID: "done-photo")]
        let photoRepository = SpyPhotoRepository()
        let sut = makeSUT(
            activeRepository: activeRepository,
            completedRepository: completedRepository,
            photoRepository: photoRepository
        )

        sut.resetToday()

        #expect(completedRepository.stored.isEmpty)
        #expect(activeRepository.stored == nil)
        #expect(photoRepository.deleted.sorted() == ["active-photo", "doc-done-photo", "done-photo"])
        #expect(sut.summary == DevStateSummary())
        #expect(sut.lastAction != nil)
    }

    @Test func resetTodayKeepsEarlierCompletions() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        let completedRepository = InMemoryCompletedChallengeRepository()
        completedRepository.stored = [makeCompletion(at: yesterday, photoID: "old"), makeCompletion(at: Date())]
        let photoRepository = SpyPhotoRepository()
        let sut = makeSUT(completedRepository: completedRepository, photoRepository: photoRepository)

        sut.resetToday()

        #expect(completedRepository.stored.map(\.photoID) == ["old"])
        #expect(!photoRepository.deleted.contains("old"))
        #expect(!photoRepository.deleted.contains("doc-old"))
        #expect(sut.summary.completionCount == 1)
        #expect(!sut.summary.hasCompletedToday)
    }

    @Test func resetTodayIsSafeWhenNothingToReset() {
        let photoRepository = SpyPhotoRepository()
        let sut = makeSUT(photoRepository: photoRepository)

        sut.resetToday()

        #expect(photoRepository.deleted.isEmpty)
        #expect(sut.summary == DevStateSummary())
    }

    @Test func resetHistoryClearsEveryCompletionAndItsPhotos() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        let completedRepository = InMemoryCompletedChallengeRepository()
        completedRepository.stored = [
            makeCompletion(at: yesterday, photoID: "old"),
            makeCompletion(at: Date(), photoID: "today"),
        ]
        let photoRepository = SpyPhotoRepository()
        let sut = makeSUT(completedRepository: completedRepository, photoRepository: photoRepository)

        sut.resetHistory()

        #expect(completedRepository.stored.isEmpty)
        #expect(photoRepository.deleted.sorted() == ["doc-old", "doc-today", "old", "today"])
        #expect(sut.summary.completionCount == 0)
        #expect(!sut.summary.hasCompletedToday)
        #expect(sut.lastAction != nil)
    }

    /// The whole point of the separate button: unlike `resetToday`, an
    /// in-progress challenge survives.
    @Test func resetHistoryLeavesTheActiveChallengeAlone() {
        let activeRepository = InMemoryActiveChallengeRepository()
        activeRepository.stored = makeActive(photoID: "active-photo")
        let completedRepository = InMemoryCompletedChallengeRepository()
        completedRepository.stored = [makeCompletion(at: Date(), photoID: "done")]
        let photoRepository = SpyPhotoRepository()
        let sut = makeSUT(
            activeRepository: activeRepository,
            completedRepository: completedRepository,
            photoRepository: photoRepository
        )

        sut.resetHistory()

        #expect(activeRepository.stored != nil)
        #expect(!photoRepository.deleted.contains("active-photo"))
        #expect(sut.summary.hasActiveChallenge)
    }

    @Test func resetHistoryIsSafeWhenThereIsNoHistory() {
        let photoRepository = SpyPhotoRepository()
        let sut = makeSUT(photoRepository: photoRepository)

        sut.resetHistory()

        #expect(photoRepository.deleted.isEmpty)
        #expect(sut.summary == DevStateSummary())
    }

    /// FR-093: the canvas holds more photos than the capture, and every one of
    /// them is a file on disk that nothing else can name once the record goes.
    @Test func resetTodayDeletesEveryPhotoTheCanvasHolds() {
        let activeRepository = InMemoryActiveChallengeRepository()
        var active = makeActive(photoID: "active-photo")
        active.document.appendPhoto("active-extra")
        // Imported, then deleted from the canvas — no layer left to name it.
        active.importedPhotoIDs = ["active-extra", "active-orphan"]
        activeRepository.stored = active
        let completedRepository = InMemoryCompletedChallengeRepository()
        completedRepository.stored = [
            makeCompletion(at: Date(), photoID: "done", extraPhotoIDs: ["done-extra"]),
        ]
        let photoRepository = SpyPhotoRepository()
        let sut = makeSUT(
            activeRepository: activeRepository,
            completedRepository: completedRepository,
            photoRepository: photoRepository
        )

        sut.resetToday()

        #expect(photoRepository.deleted.sorted() == [
            "active-extra", "active-orphan", "active-photo",
            "doc-done", "done", "done-extra",
        ])
    }

    @Test func summaryReflectsStoresAfterRefresh() {
        let activeRepository = InMemoryActiveChallengeRepository()
        activeRepository.stored = makeActive(photoID: nil)
        let completedRepository = InMemoryCompletedChallengeRepository()
        completedRepository.stored = [makeCompletion(at: Date())]
        let sut = makeSUT(activeRepository: activeRepository, completedRepository: completedRepository)

        sut.refresh()

        #expect(sut.summary == DevStateSummary(
            completionCount: 1,
            hasCompletedToday: true,
            hasActiveChallenge: true,
            activeHasPhoto: false
        ))
    }
}
