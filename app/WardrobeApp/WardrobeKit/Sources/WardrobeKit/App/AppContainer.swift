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
    private let session: SessionService
    private let sessionTokenRepository: SessionTokenRepository
    private let cameraService: CameraService

    public init(
        challengeRepository: ChallengeRepository = MockChallengeRepository(),
        activeChallengeRepository: ActiveChallengeRepository = FileActiveChallengeRepository(),
        completedChallengeRepository: CompletedChallengeRepository = UserDefaultsCompletedChallengeRepository(),
        photoRepository: PhotoRepository = FilePhotoRepository(),
        preferencesRepository: AccountPreferencesRepository? = nil,
        completionPreviewRepository: CompletionPreviewRepository = FileCompletionPreviewRepository(),
        appleAccountRepository: AppleAccountRepository = StoredAppleAccountRepository(),
        session: SessionService? = nil,
        sessionTokenRepository: SessionTokenRepository = StoredSessionTokenRepository(),
        cameraService: CameraService? = nil
    ) {
        self.challengeRepository = challengeRepository
        self.activeChallengeRepository = activeChallengeRepository
        self.completedChallengeRepository = completedChallengeRepository
        self.photoRepository = photoRepository
        let preferencesRepository = preferencesRepository
            ?? UserDefaultsAccountPreferencesRepository(outbox: Self.makeOutboxRepository())
        self.preferencesRepository = preferencesRepository
        self.completionPreviewRepository = completionPreviewRepository
        self.sessionTokenRepository = sessionTokenRepository
        let session = session ?? Self.defaultSession(tokens: sessionTokenRepository)
        self.session = session
        onboarding = OnboardingModel(
            preferences: preferencesRepository,
            accounts: appleAccountRepository,
            session: session
        )
        self.cameraService = cameraService ?? Self.defaultCameraService()
    }

    var baseURL: URL {
        Self.apiBaseURL
    }

    func makeUnauthenticatedClient() -> APIClient {
        URLSessionAPIClient(baseURL: Self.apiBaseURL)
    }

    public func makeAuthenticatedClient() -> AuthenticatedAPIClient {
        SessionedAPIClient(client: URLSessionAPIClient(baseURL: Self.apiBaseURL), session: session)
    }

    private static func defaultSession(tokens: SessionTokenRepository) -> SessionService {
        ServerSessionService(
            client: URLSessionAPIClient(baseURL: apiBaseURL),
            identities: StoredAnonymousIdentityRepository(),
            tokens: tokens
        )
    }

    private static var apiBaseURL: URL {
        let configured = Bundle.main.object(forInfoDictionaryKey: "APIBaseURL") as? String
        guard let configured, let url = URL(string: configured), url.host()?.isEmpty == false else {
            Log.network.error("APIBaseURL is missing or unusable; the app stays local-only")
            // A compile-time constant that provably parses; every request against
            // it then fails and the app runs local-only, which is the intent.
            return URL(string: "http://localhost")!
        }
        return url
    }

    public func startSession() async {
        await session.start()
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
            thumbnails: garmentThumbnailRepository,
            preferences: preferencesRepository
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

    public func makeCropViewModel(photoID: UUID) -> CropViewModel {
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

    public func makeAddByCameraViewModel() -> AddByCameraViewModel {
        AddByCameraViewModel(camera: makeCameraService(), review: makeGarmentReviewModel())
    }

    public func makeGarmentReviewModel() -> GarmentReviewModel {
        GarmentReviewModel(
            scanner: makeGarmentScanService(allowsMatching: false),
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

    public func makeGarmentScanService(allowsMatching: Bool = true) -> GarmentScanService {
        WardrobeGarmentScanService(
            segmentation: Self.defaultSegmentation(),
            thumbnails: garmentThumbnailRepository,
            repository: makeWardrobeItemRepository(),
            allowsMatching: allowsMatching
        )
    }

    private let garmentThumbnailRepository: GarmentThumbnailRepository = FileGarmentThumbnailRepository()

    private func makeWardrobeItemRepository() -> WardrobeItemRepository {
        SwiftDataWardrobeItemRepository(context: Self.wardrobeContext, outbox: Self.makeOutboxRepository())
    }

    public func makeOutboxRepository() -> OutboxRepository {
        Self.makeOutboxRepository()
    }

    static func makeOutboxRepository() -> OutboxRepository {
        StoredOutboxRepository(store: SwiftDataOutboxStore(context: wardrobeContext))
    }

    // ponytail: one instance, deliberately. A coordinator built per call would
    // hold its own inFlight and the single-flight guarantee would be a no-op.
    private(set) lazy var syncCoordinator: any SyncCoordinator = ServerSyncCoordinator(
        client: makeAuthenticatedClient(),
        outbox: makeOutboxRepository(),
        feed: makeChangeFeedRepository()
    )

    private(set) lazy var reachability: any ReachabilityService = PathReachabilityService()

    func makeChangeFeedRepository() -> ChangeFeedRepository {
        ServerChangeFeedRepository(
            client: makeAuthenticatedClient(),
            cursor: SwiftDataCursorStore(context: Self.wardrobeContext)
        )
    }

    @MainActor
    private static let wardrobeContext = ModelContext(wardrobeContainer)

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
            onboarding: onboarding,
            session: session,
            client: makeAuthenticatedClient(),
            plainClient: makeUnauthenticatedClient(),
            baseURL: Self.apiBaseURL,
            tokens: sessionTokenRepository,
            outboxRepository: makeOutboxRepository(),
            feed: makeChangeFeedRepository(),
            coordinator: syncCoordinator,
            diagnosticsStore: diagnostics
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

// MARK: - Diagnostics

extension AppContainer {
    var diagnostics: any DiagnosticsStore {
        Self.diagnosticsStore
    }

    func startDiagnostics() {
        let store = diagnostics
        Log.diagnosticsSink = { error, context in
            Task { @MainActor in
                try? store.record(error, context: context, at: Date())
            }
        }
    }

    @MainActor
    private static let diagnosticsStore: any DiagnosticsStore =
        SwiftDataDiagnosticsStore(container: wardrobeContainer)
}
