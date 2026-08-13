import Foundation

/// Composition root. Owns dependency construction so views and view models
/// stay injectable and testable.
@MainActor
public final class AppContainer {
    private let challengeRepository: ChallengeRepository
    private let activeChallengeRepository: ActiveChallengeRepository
    private let completedChallengeRepository: CompletedChallengeRepository
    private let photoRepository: PhotoRepository
    private let cameraService: CameraService

    public init(
        challengeRepository: ChallengeRepository = MockChallengeRepository(),
        activeChallengeRepository: ActiveChallengeRepository = UserDefaultsActiveChallengeRepository(),
        completedChallengeRepository: CompletedChallengeRepository = UserDefaultsCompletedChallengeRepository(),
        photoRepository: PhotoRepository = FilePhotoRepository(),
        cameraService: CameraService? = nil
    ) {
        self.challengeRepository = challengeRepository
        self.activeChallengeRepository = activeChallengeRepository
        self.completedChallengeRepository = completedChallengeRepository
        self.photoRepository = photoRepository
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
            challengeRepository: challengeRepository,
            activeRepository: activeChallengeRepository,
            completedRepository: completedChallengeRepository,
            photoRepository: photoRepository
        )
    }

    public func makeCaptureFlowViewModel(challenge: ActiveChallenge) -> CaptureFlowViewModel {
        CaptureFlowViewModel(
            challenge: challenge,
            camera: cameraService,
            activeRepository: activeChallengeRepository,
            completedRepository: completedChallengeRepository,
            photoRepository: photoRepository,
            library: Self.defaultPhotoLibrary()
        )
    }

    private static func defaultPhotoLibrary() -> PhotoLibraryService {
        #if os(iOS)
            PHPhotoLibraryService()
        #else
            NoopPhotoLibraryService()
        #endif
    }

    public func makeEditorViewModel(challenge: ActiveChallenge) -> EditorViewModel {
        EditorViewModel(
            challenge: challenge,
            activeRepository: activeChallengeRepository,
            photoRepository: photoRepository,
            librarySaver: Self.defaultLibrarySaver()
        )
    }

    public func makeDevMenuViewModel() -> DevMenuViewModel {
        DevMenuViewModel(
            activeRepository: activeChallengeRepository,
            completedRepository: completedChallengeRepository,
            photoRepository: photoRepository
        )
    }

    private static func defaultLibrarySaver() -> PhotoLibrarySaveService {
        #if os(iOS)
            PHPhotoLibrarySaveService()
        #else
            NoopPhotoLibrarySaveService()
        #endif
    }
}
