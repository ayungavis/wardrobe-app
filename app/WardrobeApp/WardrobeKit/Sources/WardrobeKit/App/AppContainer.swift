import Foundation
import SwiftData

@MainActor
public final class AppContainer {
    private let challengeRepository: ChallengeRepository
    private let activeChallengeRepository: ActiveChallengeRepository
    private let completedChallengeRepository: CompletedChallengeRepository
    private let photoRepository: PhotoRepository
    let preferencesRepository: AccountPreferencesRepository
    private let completionPreviewRepository: CompletionPreviewRepository
    let onboarding: OnboardingModel
    private let cameraService: CameraService

    public init(
        challengeRepository: ChallengeRepository = MockChallengeRepository(),
        activeChallengeRepository: ActiveChallengeRepository = FileActiveChallengeRepository(),
        completedChallengeRepository: CompletedChallengeRepository = UserDefaultsCompletedChallengeRepository(),
        photoRepository: PhotoRepository = FilePhotoRepository(),
        preferencesRepository: AccountPreferencesRepository = UserDefaultsAccountPreferencesRepository(),
        completionPreviewRepository: CompletionPreviewRepository = FileCompletionPreviewRepository(),
        appleAccountRepository: AppleAccountRepository = KeychainAppleAccountRepository(),
        cameraService: CameraService? = nil
    ) {
        self.challengeRepository = challengeRepository
        self.activeChallengeRepository = activeChallengeRepository
        self.completedChallengeRepository = completedChallengeRepository
        self.photoRepository = photoRepository
        self.preferencesRepository = preferencesRepository
        self.completionPreviewRepository = completionPreviewRepository
        onboarding = OnboardingModel(
            preferences: preferencesRepository, accounts: appleAccountRepository
        )
        self.cameraService = cameraService ?? Self.defaultCameraService()
    }

    private static func defaultCameraService() -> CameraService {
        #if os(iOS) && !targetEnvironment(simulator)
            AVFCameraService()
        #else
            SampleCameraService()
        #endif
    }

    public func flushDrafts() async {
        await activeChallengeRepository.flush()
    }

    public func makeOnboardingViewModel() -> OnboardingViewModel {
        OnboardingViewModel(onboarding: onboarding)
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
            previews: completionPreviewRepository,
            library: Self.defaultPhotoLibrary(),
            scanner: makeGarmentScanService(),
            wardrobeRepository: makeWardrobeItemRepository(),
            thumbnails: garmentThumbnailRepository
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
            librarySaver: Self.defaultLibrarySaver(),
            preferencesRepository: preferencesRepository
        )
    }

    public func makeCropViewModel(photoID: String) -> CropViewModel {
        CropViewModel(photoID: photoID, photoRepository: photoRepository)
    }

    public func makeWardrobeViewModel() -> WardrobeViewModel {
        WardrobeViewModel(
            thumbnails: garmentThumbnailRepository,
            repository: makeWardrobeItemRepository()
        )
    }

    public func makeWardrobeItemDetailViewModel(itemID: UUID) -> WardrobeItemDetailViewModel {
        WardrobeItemDetailViewModel(
            itemID: itemID,
            repository: makeWardrobeItemRepository(),
            thumbnails: garmentThumbnailRepository
        )
    }

    public func makeGarmentReviewModel() -> GarmentReviewModel {
        GarmentReviewModel(
            scanner: makeGarmentScanService(),
            photoRepository: photoRepository,
            wardrobeRepository: makeWardrobeItemRepository(),
            thumbnails: garmentThumbnailRepository
        )
    }

    func makeMatchBenchmarkViewModel() -> MatchBenchmarkViewModel {
        MatchBenchmarkViewModel(
            scanner: makeGarmentScanService(),
            thumbnails: garmentThumbnailRepository
        )
    }

    public func makeGarmentScanService() -> GarmentScanService {
        WardrobeGarmentScanService(
            segmentation: Self.defaultSegmentation(),
            thumbnails: garmentThumbnailRepository,
            repository: makeWardrobeItemRepository()
        )
    }

    private let garmentThumbnailRepository: GarmentThumbnailRepository = FileGarmentThumbnailRepository()

    private func makeWardrobeItemRepository() -> WardrobeItemRepository {
        SwiftDataWardrobeItemRepository(container: Self.wardrobeContainer)
    }

    private static let wardrobeContainer: ModelContainer = {
        do {
            return try ModelContainer(for: SwiftDataWardrobeItemRepository.schema)
        } catch {
            Log.report(error)
            // `ModelContainer` has no non-throwing init, and a SwiftData that
            // cannot even build one in memory leaves nothing to fall back to.
            // swiftlint:disable:next force_try
            return try! ModelContainer(
                for: SwiftDataWardrobeItemRepository.schema,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
        }
    }()

    private static func defaultSegmentation() -> GarmentSegmentationService {
        #if os(iOS)
            FASHNGarmentSegmentationService()
        #else
            NoopGarmentSegmentationService()
        #endif
    }

    public func makeDevMenuViewModel() -> DevMenuViewModel {
        DevMenuViewModel(
            activeRepository: activeChallengeRepository,
            completedRepository: completedChallengeRepository,
            photoRepository: photoRepository,
            wardrobeRepository: makeWardrobeItemRepository(),
            thumbnails: garmentThumbnailRepository,
            previews: completionPreviewRepository,
            onboarding: onboarding
        )
    }

    private static func defaultLibrarySaver() -> PhotoLibrarySaveService {
        #if os(iOS)
            PHPhotoLibrarySaveService()
        #else
            NoopPhotoLibrarySaveService()
        #endif
    }

    public func makeCameraService() -> CameraService {
        cameraService
    }

    public func makeHistoryViewModel() -> HistoryViewModel {
        HistoryViewModel(
            completedRepository: completedChallengeRepository,
            photoRepository: photoRepository,
            wardrobeRepository: makeWardrobeItemRepository(),
            thumbnails: garmentThumbnailRepository,
            previews: completionPreviewRepository
        )
    }
}
