import Foundation

/// Composition root. Owns dependency construction so views and view models
/// stay injectable and testable.
@MainActor
public final class AppContainer {
    private let challengeRepository: ChallengeRepository
    private let activeChallengeStore: ActiveChallengeStore
    private let completedChallengeStore: CompletedChallengeStore
    private let photoStore: PhotoStore
    private let cameraService: CameraService

    public init(
        challengeRepository: ChallengeRepository = MockChallengeRepository(),
        activeChallengeStore: ActiveChallengeStore = UserDefaultsActiveChallengeStore(),
        completedChallengeStore: CompletedChallengeStore = UserDefaultsCompletedChallengeStore(),
        photoStore: PhotoStore = FilePhotoStore(),
        cameraService: CameraService? = nil
    ) {
        self.challengeRepository = challengeRepository
        self.activeChallengeStore = activeChallengeStore
        self.completedChallengeStore = completedChallengeStore
        self.photoStore = photoStore
        self.cameraService = cameraService ?? Self.defaultCameraService()
    }

    private static func defaultCameraService() -> CameraService {
        #if os(iOS) && !targetEnvironment(simulator)
            AVFCameraService()
        #else
            SampleCameraService()
        #endif
    }

    public func makeChallengeViewModel() -> ChallengeViewModel {
        ChallengeViewModel(
            repository: challengeRepository,
            store: activeChallengeStore,
            completedStore: completedChallengeStore,
            photoStore: photoStore
        )
    }

    public func makeCaptureFlowViewModel(challenge: ActiveChallenge) -> CaptureFlowViewModel {
        CaptureFlowViewModel(
            challenge: challenge,
            camera: cameraService,
            store: activeChallengeStore,
            completedStore: completedChallengeStore,
            photoStore: photoStore,
            library: Self.defaultPhotoLibrary()
        )
    }

    private static func defaultPhotoLibrary() -> PhotoLibraryBrowsing {
        #if os(iOS)
            PHPhotoLibraryBrowser()
        #else
            NoopPhotoLibraryBrowser()
        #endif
    }

    public func makeEditorViewModel(challenge: ActiveChallenge) -> EditorViewModel {
        EditorViewModel(
            challenge: challenge,
            store: activeChallengeStore,
            photoStore: photoStore,
            librarySaver: Self.defaultLibrarySaver()
        )
    }

    private static func defaultLibrarySaver() -> PhotoLibrarySaving {
        #if os(iOS)
            PHPhotoLibrarySaver()
        #else
            NoopPhotoLibrarySaver()
        #endif
    }
}
