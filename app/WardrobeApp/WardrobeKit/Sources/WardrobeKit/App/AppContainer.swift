import Foundation
import SwiftData

/// Composition root. Owns dependency construction so views and view models
/// stay injectable and testable.
@MainActor
public final class AppContainer {
    private let challengeRepository: ChallengeRepository
    private let activeChallengeRepository: ActiveChallengeRepository
    private let completedChallengeRepository: CompletedChallengeRepository
    private let photoRepository: PhotoRepository
    let preferencesRepository: AccountPreferencesRepository
    private let completionPreviewRepository: CompletionPreviewRepository
    private let cameraService: CameraService

    public init(
        challengeRepository: ChallengeRepository = MockChallengeRepository(),
        activeChallengeRepository: ActiveChallengeRepository = FileActiveChallengeRepository(),
        completedChallengeRepository: CompletedChallengeRepository = UserDefaultsCompletedChallengeRepository(),
        photoRepository: PhotoRepository = FilePhotoRepository(),
        preferencesRepository: AccountPreferencesRepository = UserDefaultsAccountPreferencesRepository(),
        completionPreviewRepository: CompletionPreviewRepository = FileCompletionPreviewRepository(),
        cameraService: CameraService? = nil
    ) {
        self.challengeRepository = challengeRepository
        self.activeChallengeRepository = activeChallengeRepository
        self.completedChallengeRepository = completedChallengeRepository
        self.photoRepository = photoRepository
        self.preferencesRepository = preferencesRepository
        self.completionPreviewRepository = completionPreviewRepository
        self.cameraService = cameraService ?? Self.defaultCameraService()
    }

    private static func defaultCameraService() -> CameraService {
        #if os(iOS) && !targetEnvironment(simulator)
            AVFCameraService()
        #else
            SampleCameraService()
        #endif
    }

    /// Makes the in-progress draft durable. Called when the app leaves the
    /// screen, which is the last moment it is certain to get.
    public func flushDrafts() async {
        await activeChallengeRepository.flush()
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

    /// Internal: the benchmark is a dev tool and never leaves the package.
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

    /// Built once per process; `ModelContainer` is Sendable and cheap to share.
    private static let wardrobeContainer: ModelContainer = {
        do {
            return try ModelContainer(for: SwiftDataWardrobeItemRepository.schema)
        } catch {
            Log.report(error)
            // Last resort after the on-disk container failed: an in-memory one
            // keeps the app usable for this session. `ModelContainer` has no
            // non-throwing initialiser, and failing here means SwiftData itself
            // is unusable — there is nothing left to fall back to.
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
            previews: completionPreviewRepository
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
