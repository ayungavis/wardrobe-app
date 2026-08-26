import Foundation
import SwiftData
@testable import WardrobeKit

// Shared by the capture-flow suites, which are split by subject rather than
// kept in one file — nine collaborators and four stages outgrew a single type.

@MainActor
func makeCaptureFlowSUT(
    challenge: ActiveChallenge = ActiveChallenge(card: ChallengeCard(prompt: "x"), acceptedAt: .distantPast),
    camera: FakeCameraService = FakeCameraService(),
    activeRepository: InMemoryActiveChallengeRepository = InMemoryActiveChallengeRepository(),
    completedRepository: InMemoryCompletedChallengeRepository = InMemoryCompletedChallengeRepository(),
    photoRepository: SpyPhotoRepository = SpyPhotoRepository(),
    previews: InMemoryCompletionPreviewRepository = InMemoryCompletionPreviewRepository(),
    library: FakePhotoLibrary = FakePhotoLibrary(),
    scanner: FakeGarmentScanService = FakeGarmentScanService(),
    wardrobeRepository: InMemoryWardrobeItemRepository = InMemoryWardrobeItemRepository(),
    thumbnails: any GarmentThumbnailRepository = InMemoryGarmentThumbnailRepository(),
    outbox: any OutboxRepository = StoredOutboxRepository(store: InMemoryOutboxStore()),
    uploads: any MediaUploadRepository = makeInMemoryUploads()
) -> CaptureFlowViewModel {
    CaptureFlowViewModel(
        challenge: challenge,
        camera: camera,
        activeRepository: activeRepository,
        completedRepository: completedRepository,
        photoRepository: photoRepository,
        previews: previews,
        library: library,
        scanner: scanner,
        wardrobeRepository: wardrobeRepository,
        thumbnails: thumbnails,
        preferences: InMemoryAccountPreferencesRepository(),
        outbox: outbox,
        uploads: uploads
    )
}

/// A flow that already has a photo and permission — the state the editor and
/// the ✓ actually run in.
@MainActor
func makeEditorStageCaptureFlowSUT(
    activeRepository: InMemoryActiveChallengeRepository = InMemoryActiveChallengeRepository(),
    completedRepository: InMemoryCompletedChallengeRepository = InMemoryCompletedChallengeRepository(),
    photoRepository: SpyPhotoRepository = SpyPhotoRepository(),
    previews: InMemoryCompletionPreviewRepository = InMemoryCompletionPreviewRepository(),
    scanner: FakeGarmentScanService = FakeGarmentScanService(),
    thumbnails: any GarmentThumbnailRepository = InMemoryGarmentThumbnailRepository(),
    outbox: any OutboxRepository = StoredOutboxRepository(store: InMemoryOutboxStore()),
    uploads: any MediaUploadRepository = makeInMemoryUploads()
) -> CaptureFlowViewModel {
    var challenge = ActiveChallenge(card: ChallengeCard(prompt: "x"), acceptedAt: .distantPast)
    challenge.photoID = UUID.v7()
    activeRepository.stored = challenge
    let camera = FakeCameraService()
    camera.permission = .granted
    return makeCaptureFlowSUT(
        challenge: challenge,
        camera: camera,
        activeRepository: activeRepository,
        completedRepository: completedRepository,
        photoRepository: photoRepository,
        previews: previews,
        scanner: scanner,
        thumbnails: thumbnails,
        outbox: outbox,
        uploads: uploads
    )
}

/// The ✓ path over **real** SwiftData repositories sharing one ModelContext.
/// Atomicity cannot be tested against fakes that have no transaction to roll back.
@MainActor
struct TransactionalCaptureFlow {
    let flow: CaptureFlowViewModel
    let outbox: StoredOutboxRepository
    let uploads: StoredMediaUploadRepository
    let completions: SwiftDataCompletedChallengeRepository
    let wardrobe: SwiftDataWardrobeItemRepository
}

@MainActor
func makeTransactionalCaptureFlow(
    scanner: FakeGarmentScanService = FakeGarmentScanService(),
    thumbnails: any GarmentThumbnailRepository = InMemoryGarmentThumbnailRepository()
) throws -> TransactionalCaptureFlow {
    let container = try ModelContainer(
        for: SwiftDataWardrobeItemRepository.schema,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = ModelContext(container)
    let outbox = StoredOutboxRepository(store: SwiftDataOutboxStore(context: context))
    let uploads = StoredMediaUploadRepository(
        store: SwiftDataMediaUploadStore(context: context),
        photos: SpyPhotoRepository(),
        previews: InMemoryCompletionPreviewRepository(),
        thumbnails: InMemoryGarmentThumbnailRepository()
    )
    let completions = SwiftDataCompletedChallengeRepository(context: context)
    let wardrobe = SwiftDataWardrobeItemRepository(context: context, outbox: outbox)

    var challenge = ActiveChallenge(card: ChallengeCard(prompt: "x"), acceptedAt: .distantPast)
    challenge.photoID = UUID.v7()
    let activeRepository = InMemoryActiveChallengeRepository()
    activeRepository.stored = challenge
    let camera = FakeCameraService()
    camera.permission = .granted

    let flow = CaptureFlowViewModel(
        challenge: challenge,
        camera: camera,
        activeRepository: activeRepository,
        completedRepository: completions,
        photoRepository: SpyPhotoRepository(),
        previews: InMemoryCompletionPreviewRepository(),
        library: FakePhotoLibrary(),
        scanner: scanner,
        wardrobeRepository: wardrobe,
        thumbnails: thumbnails,
        preferences: InMemoryAccountPreferencesRepository(),
        outbox: outbox,
        uploads: uploads
    )
    return TransactionalCaptureFlow(
        flow: flow, outbox: outbox, uploads: uploads, completions: completions, wardrobe: wardrobe
    )
}
