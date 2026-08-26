import Foundation

// MARK: - Restore and the change feed

extension AppContainer {
    func makeMediaDownloadRepository() -> MediaDownloadRepository {
        StoredMediaDownloadRepository(store: SwiftDataMediaDownloadStore(context: Self.wardrobeContext))
    }

    func makeRestoreService() -> RestoreService {
        LocalRestoreService(
            wardrobe: SwiftDataWardrobeItemRepository(context: Self.wardrobeContext),
            completions: SwiftDataCompletedChallengeRepository(context: Self.wardrobeContext),
            preferences: preferencesRepository,
            downloads: makeMediaDownloadRepository(),
            media: makeMediaRepository(),
            photos: photoRepository,
            previews: completionPreviewRepository,
            thumbnails: garmentThumbnailRepository
        )
    }

    func makeChangeFeedRepository() -> ChangeFeedRepository {
        ServerChangeFeedRepository(
            client: makeAuthenticatedClient(),
            cursor: SwiftDataCursorStore(context: Self.wardrobeContext)
        )
    }
}
