import Foundation
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
    thumbnails: InMemoryGarmentThumbnailRepository = InMemoryGarmentThumbnailRepository()
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
        thumbnails: thumbnails
    )
}

/// A flow that already has a photo and permission — the state the editor and
/// the ✓ actually run in.
@MainActor
func makeEditorStageCaptureFlowSUT(
    activeRepository: InMemoryActiveChallengeRepository = InMemoryActiveChallengeRepository(),
    completedRepository: InMemoryCompletedChallengeRepository = InMemoryCompletedChallengeRepository(),
    photoRepository: SpyPhotoRepository = SpyPhotoRepository(),
    previews: InMemoryCompletionPreviewRepository = InMemoryCompletionPreviewRepository()
) -> CaptureFlowViewModel {
    var challenge = ActiveChallenge(card: ChallengeCard(prompt: "x"), acceptedAt: .distantPast)
    challenge.photoID = UUID().uuidString
    activeRepository.stored = challenge
    let camera = FakeCameraService()
    camera.permission = .granted
    return makeCaptureFlowSUT(
        challenge: challenge,
        camera: camera,
        activeRepository: activeRepository,
        completedRepository: completedRepository,
        photoRepository: photoRepository,
        previews: previews
    )
}
