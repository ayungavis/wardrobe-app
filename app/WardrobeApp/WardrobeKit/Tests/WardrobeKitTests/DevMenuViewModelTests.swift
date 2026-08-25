import Foundation
import Testing
@testable import WardrobeKit

@MainActor
struct DevMenuViewModelTests {
    @Test func resetWardrobeClearsItemsAndTheirImages() throws {
        let wardrobe = InMemoryWardrobeItemRepository()
        let thumbnails = InMemoryGarmentThumbnailRepository()
        let item = makeDevMenuWardrobeItem()
        try wardrobe.insert(item, fingerprint: nil, wear: WearRecord(itemID: item.id, wornAt: Date()))
        thumbnails.files[item.cutoutFile] = Data([0x01])
        let sut = makeDevMenuViewModel(wardrobeRepository: wardrobe, thumbnails: thumbnails)

        sut.resetWardrobe()

        #expect(try wardrobe.items().isEmpty)
        #expect(thumbnails.files.isEmpty)
        #expect(thumbnails.deleteAllCount == 1)
        #expect(sut.summary.wardrobeItemCount == 0)
        #expect(sut.lastAction != nil)
    }

    @Test func resetOnboardingSignsOutAndReopensOnboarding() async throws {
        let preferences = InMemoryAccountPreferencesRepository()
        let accounts = StoredAppleAccountRepository(store: InMemorySecureStore())
        let onboarding = OnboardingModel(preferences: preferences, accounts: accounts, session: FakeSessionService())
        try await onboarding.signIn(
            identityToken: "jwt", nonce: "raw", profile: AppleProfile(fullName: nil, email: nil)
        )
        let sut = makeDevMenuViewModel(onboarding: onboarding)

        await sut.resetOnboarding()

        #expect(onboarding.isCompleted == false)
        #expect(preferences.stored.hasCompletedOnboarding == false)
        #expect(accounts.load() == nil)
        #expect(sut.summary.hasCompletedOnboarding == false)
        #expect(sut.summary.isSignedIn == false)
        #expect(sut.lastAction != nil)
    }

    @Test func summaryReportsOnboardingAndSignIn() async throws {
        let onboarding = OnboardingModel(
            preferences: InMemoryAccountPreferencesRepository(),
            accounts: StoredAppleAccountRepository(store: InMemorySecureStore()),
            session: FakeSessionService()
        )
        try await onboarding.signIn(
            identityToken: "jwt", nonce: "raw", profile: AppleProfile(fullName: nil, email: nil)
        )
        let sut = makeDevMenuViewModel(onboarding: onboarding)

        sut.refresh()

        #expect(sut.summary.hasCompletedOnboarding)
        #expect(sut.summary.isSignedIn)
    }

    @Test func summaryCountsWardrobeItems() throws {
        let wardrobe = InMemoryWardrobeItemRepository()
        let item = makeDevMenuWardrobeItem()
        try wardrobe.insert(item, fingerprint: nil, wear: WearRecord(itemID: item.id, wornAt: Date()))
        let sut = makeDevMenuViewModel(wardrobeRepository: wardrobe)

        sut.refresh()

        #expect(sut.summary.wardrobeItemCount == 1)
    }

    /// The document carries its own photo, distinct from the capture — that is
    /// the shape FR-093 produces, and the only one that can catch a leak.
    private func makeCompletion(
        at date: Date,
        named name: String = UUID().uuidString,
        extraPhotoIDs: [UUID] = []
    ) -> CompletedChallenge {
        let photoID = id(name)
        var document = EditorDocument.fixture(photoID: id("doc-\(name)"))
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

    private func makeActive(photoID: UUID?) -> ActiveChallenge {
        var challenge = ActiveChallenge(card: ChallengeCard(prompt: "x"), acceptedAt: .distantPast)
        challenge.photoID = photoID
        return challenge
    }

    @Test func resetTodayClearsCompletionActiveChallengeAndPhotos() {
        let activeRepository = InMemoryActiveChallengeRepository()
        activeRepository.stored = makeActive(photoID: id("active-photo"))
        let completedRepository = InMemoryCompletedChallengeRepository()
        completedRepository.stored = [makeCompletion(at: Date(), named: "done-photo")]
        let photoRepository = SpyPhotoRepository()
        let sut = makeDevMenuViewModel(
            activeRepository: activeRepository,
            completedRepository: completedRepository,
            photoRepository: photoRepository
        )

        sut.resetToday()

        #expect(completedRepository.stored.isEmpty)
        #expect(activeRepository.stored == nil)
        #expect(photoRepository.deleted.sorted() == [id("active-photo"), id("doc-done-photo"), id("done-photo")].sorted())
        #expect(sut.summary == DevStateSummary())
        #expect(sut.lastAction != nil)
    }

    @Test func resetTodayKeepsEarlierCompletions() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        let completedRepository = InMemoryCompletedChallengeRepository()
        completedRepository.stored = [makeCompletion(at: yesterday, named: "old"), makeCompletion(at: Date())]
        let photoRepository = SpyPhotoRepository()
        let sut = makeDevMenuViewModel(completedRepository: completedRepository, photoRepository: photoRepository)

        sut.resetToday()

        #expect(completedRepository.stored.map(\.photoID) == [id("old")])
        #expect(!photoRepository.deleted.contains(id("old")))
        #expect(!photoRepository.deleted.contains(id("doc-old")))
        #expect(sut.summary.completionCount == 1)
        #expect(!sut.summary.hasCompletedToday)
    }

    @Test func resetTodayIsSafeWhenNothingToReset() {
        let photoRepository = SpyPhotoRepository()
        let sut = makeDevMenuViewModel(photoRepository: photoRepository)

        sut.resetToday()

        #expect(photoRepository.deleted.isEmpty)
        #expect(sut.summary == DevStateSummary())
    }

    @Test func resetHistoryClearsEveryCompletionAndItsPhotos() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        let completedRepository = InMemoryCompletedChallengeRepository()
        completedRepository.stored = [
            makeCompletion(at: yesterday, named: "old"),
            makeCompletion(at: Date(), named: "today"),
        ]
        let photoRepository = SpyPhotoRepository()
        let sut = makeDevMenuViewModel(completedRepository: completedRepository, photoRepository: photoRepository)

        sut.resetHistory()

        #expect(completedRepository.stored.isEmpty)
        #expect(photoRepository.deleted.sorted() == [id("doc-old"), id("doc-today"), id("old"), id("today")].sorted())
        #expect(sut.summary.completionCount == 0)
        #expect(!sut.summary.hasCompletedToday)
        #expect(sut.lastAction != nil)
    }

    /// The whole point of the separate button: unlike `resetToday`, an
    /// in-progress challenge survives.
    /// A preview outlives its completion unless the reset takes it too, and an
    /// orphaned render is a file nothing can ever name again.
    @Test func resetHistoryDeletesTheStoredPreviews() throws {
        let previews = InMemoryCompletionPreviewRepository()
        let file = try previews.save(Data([0x01]), id: UUID())
        let completedRepository = InMemoryCompletedChallengeRepository()
        var completion = makeCompletion(at: Date(), named: "done")
        completion.previewFile = file
        completedRepository.stored = [completion]
        let sut = makeDevMenuViewModel(completedRepository: completedRepository, previews: previews)

        sut.resetHistory()

        #expect(previews.files.isEmpty)
        #expect(previews.deleteAllCount == 1)
    }

    @Test func resetTodayDeletesTodaysPreviewAndKeepsTheRest() throws {
        let previews = InMemoryCompletionPreviewRepository()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        let todayFile = try previews.save(Data([0x01]), id: UUID())
        let oldFile = try previews.save(Data([0x02]), id: UUID())
        var today = makeCompletion(at: Date(), named: "today")
        today.previewFile = todayFile
        var old = makeCompletion(at: yesterday, named: "old")
        old.previewFile = oldFile
        let completedRepository = InMemoryCompletedChallengeRepository()
        completedRepository.stored = [old, today]
        let sut = makeDevMenuViewModel(completedRepository: completedRepository, previews: previews)

        sut.resetToday()

        #expect(previews.files.keys.sorted() == [oldFile])
    }

    @Test func resetHistoryLeavesTheActiveChallengeAlone() {
        let activeRepository = InMemoryActiveChallengeRepository()
        activeRepository.stored = makeActive(photoID: id("active-photo"))
        let completedRepository = InMemoryCompletedChallengeRepository()
        completedRepository.stored = [makeCompletion(at: Date(), named: "done")]
        let photoRepository = SpyPhotoRepository()
        let sut = makeDevMenuViewModel(
            activeRepository: activeRepository,
            completedRepository: completedRepository,
            photoRepository: photoRepository
        )

        sut.resetHistory()

        #expect(activeRepository.stored != nil)
        #expect(!photoRepository.deleted.contains(id("active-photo")))
        #expect(sut.summary.hasActiveChallenge)
    }

    @Test func resetHistoryIsSafeWhenThereIsNoHistory() {
        let photoRepository = SpyPhotoRepository()
        let sut = makeDevMenuViewModel(photoRepository: photoRepository)

        sut.resetHistory()

        #expect(photoRepository.deleted.isEmpty)
        #expect(sut.summary == DevStateSummary())
    }

    /// FR-093: the canvas holds more photos than the capture, and every one of
    /// them is a file on disk that nothing else can name once the record goes.
    @Test func resetTodayDeletesEveryPhotoTheCanvasHolds() {
        let activeRepository = InMemoryActiveChallengeRepository()
        var active = makeActive(photoID: id("active-photo"))
        active.document.appendPhoto(id("active-extra"))
        // Imported, then deleted from the canvas — no layer left to name it.
        active.importedPhotoIDs = [id("active-extra"), id("active-orphan")]
        activeRepository.stored = active
        let completedRepository = InMemoryCompletedChallengeRepository()
        completedRepository.stored = [
            makeCompletion(at: Date(), named: "done", extraPhotoIDs: [id("done-extra")]),
        ]
        let photoRepository = SpyPhotoRepository()
        let sut = makeDevMenuViewModel(
            activeRepository: activeRepository,
            completedRepository: completedRepository,
            photoRepository: photoRepository
        )

        sut.resetToday()

        #expect(photoRepository.deleted.sorted() == [
            id("active-extra"), id("active-orphan"), id("active-photo"),
            id("doc-done"), id("done"), id("done-extra"),
        ].sorted())
    }

    @Test func summaryReflectsStoresAfterRefresh() {
        let activeRepository = InMemoryActiveChallengeRepository()
        activeRepository.stored = makeActive(photoID: nil)
        let completedRepository = InMemoryCompletedChallengeRepository()
        completedRepository.stored = [makeCompletion(at: Date())]
        let sut = makeDevMenuViewModel(activeRepository: activeRepository, completedRepository: completedRepository)

        sut.refresh()

        #expect(sut.summary == DevStateSummary(
            completionCount: 1,
            hasCompletedToday: true,
            hasActiveChallenge: true,
            activeHasPhoto: false
        ))
    }
}
