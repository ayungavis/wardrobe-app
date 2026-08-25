import Foundation

// MARK: - Profile

public extension AppContainer {
    func makeProfileViewModel() -> ProfileViewModel {
        ProfileViewModel(
            accounts: appleAccountRepository,
            onboarding: onboarding,
            outbox: makeOutboxRepository(),
            uploads: makeMediaUploadRepository(),
            purge: makePurgeService(),
            accountService: ServerAccountService(client: makeAuthenticatedClient()),
            syncNow: { [syncCoordinator] in await syncCoordinator.reconcile(.manual) }
        )
    }

    private func makePurgeService() -> PurgeService {
        LocalPurgeService(
            wardrobe: makeWardrobeItemRepository(),
            thumbnails: garmentThumbnailRepository,
            completions: completedChallengeRepository,
            previews: completionPreviewRepository,
            photos: photoRepository,
            active: activeChallengeRepository,
            media: makeMediaRepository(),
            uploads: makeMediaUploadRepository(),
            outbox: makeOutboxRepository(),
            diagnostics: diagnostics,
            cursor: SwiftDataCursorStore(context: Self.wardrobeContext)
        )
    }
}
