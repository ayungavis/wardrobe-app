import Foundation
@testable import WardrobeKit

@MainActor
func makeDevMenuViewModel(
    activeRepository: InMemoryActiveChallengeRepository = InMemoryActiveChallengeRepository(),
    completedRepository: InMemoryCompletedChallengeRepository = InMemoryCompletedChallengeRepository(),
    photoRepository: SpyPhotoRepository = SpyPhotoRepository(),
    wardrobeRepository: InMemoryWardrobeItemRepository = InMemoryWardrobeItemRepository(),
    thumbnails: InMemoryGarmentThumbnailRepository = InMemoryGarmentThumbnailRepository(),
    previews: InMemoryCompletionPreviewRepository = InMemoryCompletionPreviewRepository(),
    onboarding: OnboardingModel = OnboardingModel(
        preferences: InMemoryAccountPreferencesRepository(),
        accounts: StoredAppleAccountRepository(store: InMemorySecureStore()),
        session: FakeSessionService()
    ),
    session: FakeSessionService = FakeSessionService(),
    client: any AuthenticatedAPIClient = StubAuthenticatedClient(),
    tokens: SessionTokenRepository = StoredSessionTokenRepository(store: InMemorySecureStore())
) -> DevMenuViewModel {
    DevMenuViewModel(
        activeRepository: activeRepository,
        completedRepository: completedRepository,
        photoRepository: photoRepository,
        wardrobeRepository: wardrobeRepository,
        thumbnails: thumbnails,
        previews: previews,
        onboarding: onboarding,
        session: session,
        client: client,
        plainClient: URLSessionAPIClient(baseURL: URL(string: "https://stub.invalid")!),
        baseURL: URL(string: "https://stub.invalid")!,
        tokens: tokens,
        outboxRepository: StoredOutboxRepository(store: InMemoryOutboxStore()),
        feed: ServerChangeFeedRepository(client: StubAuthenticatedClient(), cursor: InMemoryCursorStore()),
        coordinator: ServerSyncCoordinator(
            client: StubAuthenticatedClient(),
            outbox: StoredOutboxRepository(store: InMemoryOutboxStore()),
            feed: ServerChangeFeedRepository(client: StubAuthenticatedClient(), cursor: InMemoryCursorStore()),
            uploads: makeInMemoryUploads(),
            media: StubMediaRepository(),
            preferences: makeGrantedPreferences()
        ),
        diagnosticsStore: InMemoryDiagnosticsStore(),
        media: ServerMediaRepository(
            client: StubAuthenticatedClient(), cache: InMemoryMediaCacheStore()
        ),
        uploadQueue: makeInMemoryUploads()
    )
}

@MainActor
func makeDevMenuWardrobeItem() -> WardrobeItem {
    let id = UUID()
    return WardrobeItem(id: id, category: .top, cutoutFile: "\(id.uuidString).png",
                        createdAt: Date(), updatedAt: Date())
}
