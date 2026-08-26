import Foundation

public extension AppContainer {
    func makeChallengeViewModel() -> ChallengeViewModel {
        ChallengeViewModel(
            challengeRepository: challengeRepository ?? makeDeckRepository(),
            activeRepository: activeChallengeRepository,
            completedRepository: completedChallengeRepository,
            photoRepository: photoRepository,
            wardrobeRepository: makeWardrobeItemRepository(),
            thumbnails: garmentThumbnailRepository
        )
    }

    func makeDeckRepository() -> ChallengeRepository {
        FallbackChallengeRepository(
            primary: ServerChallengeRepository(client: makeAuthenticatedClient()),
            fallback: CuratedChallengeRepository()
        )
    }
}
