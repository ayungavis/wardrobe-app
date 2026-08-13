import CoreGraphics
import Foundation
import Testing
@testable import WardrobeKit

@MainActor
struct CaptureFlowViewModelTests {
    private func makeSUT(
        challenge: ActiveChallenge = ActiveChallenge(card: ChallengeCard(prompt: "x"), acceptedAt: .distantPast),
        camera: FakeCameraService = FakeCameraService(),
        activeRepository: InMemoryActiveChallengeRepository = InMemoryActiveChallengeRepository(),
        completedRepository: InMemoryCompletedChallengeRepository = InMemoryCompletedChallengeRepository(),
        photoRepository: SpyPhotoRepository = SpyPhotoRepository(),
        library: FakePhotoLibrary = FakePhotoLibrary()
    ) -> CaptureFlowViewModel {
        CaptureFlowViewModel(
            challenge: challenge,
            camera: camera,
            activeRepository: activeRepository,
            completedRepository: completedRepository,
            photoRepository: photoRepository,
            library: library
        )
    }

    // MARK: Initial stage (FR-013/014/017)

    @Test func initialStageIsConsentWhenNotDetermined() {
        let camera = FakeCameraService()
        camera.permission = .notDetermined
        #expect(makeSUT(camera: camera).stage == .consent)
    }

    @Test func initialStageIsCameraWhenGranted() {
        let camera = FakeCameraService()
        camera.permission = .granted
        #expect(makeSUT(camera: camera).stage == .camera)
    }

    @Test func initialStageIsDeniedWhenDeniedOrRestricted() {
        for permission in [CameraPermission.denied, .restricted] {
            let camera = FakeCameraService()
            camera.permission = permission
            #expect(makeSUT(camera: camera).stage == .denied)
        }
    }

    @Test func initialStageIsEditorWhenPhotoExists() {
        var challenge = ActiveChallenge(card: ChallengeCard(prompt: "x"), acceptedAt: .distantPast)
        challenge.photoID = UUID().uuidString
        #expect(makeSUT(challenge: challenge).stage == .editor)
    }

    // MARK: Consent (FR-013)

    @Test func consentContinueGrantedGoesToCamera() async {
        let camera = FakeCameraService()
        camera.permissionAfterRequest = .granted
        let sut = makeSUT(camera: camera)

        sut.consentContinue()
        await sut.consentTask?.value

        #expect(sut.stage == .camera)
    }

    @Test func consentContinueDeniedGoesToDenied() async {
        let camera = FakeCameraService()
        camera.permissionAfterRequest = .denied
        let sut = makeSUT(camera: camera)

        sut.consentContinue()
        await sut.consentTask?.value

        #expect(sut.stage == .denied)
    }

    // MARK: Permission recheck (FR-014)

    @Test func recheckFlipsCameraToDeniedAfterRevocation() {
        let camera = FakeCameraService()
        camera.permission = .granted
        let sut = makeSUT(camera: camera)
        #expect(sut.stage == .camera)

        camera.permission = .denied
        sut.recheckPermission()

        #expect(sut.stage == .denied)
    }

    @Test func recheckDoesNotTouchEditor() {
        let camera = FakeCameraService()
        camera.permission = .denied
        var challenge = ActiveChallenge(card: ChallengeCard(prompt: "x"), acceptedAt: .distantPast)
        challenge.photoID = UUID().uuidString
        let sut = makeSUT(challenge: challenge, camera: camera)

        sut.recheckPermission()

        #expect(sut.stage == .editor)
    }

    // MARK: Capture — straight to editor (FR-016, story-style)

    @Test func captureSuccessPersistsPhotoThenEditor() async {
        let camera = FakeCameraService()
        camera.permission = .granted
        let photo = Data([0xAB, 0xCD])
        camera.captureResult = .success(photo)
        let activeRepository = InMemoryActiveChallengeRepository()
        let photoRepository = SpyPhotoRepository()
        let sut = makeSUT(camera: camera, activeRepository: activeRepository, photoRepository: photoRepository)

        sut.capture()
        await sut.captureTask?.value

        let savedID = photoRepository.saved.keys.first
        #expect(savedID != nil)
        #expect(photoRepository.saved.values.first == photo)
        #expect(activeRepository.stored?.photoID == savedID)
        #expect(sut.stage == .editor)
        #expect(!sut.isCapturing)
    }

    @Test func captureFailureStaysInCameraWithError() async {
        let camera = FakeCameraService()
        camera.permission = .granted
        camera.captureResult = .failure(AppError.captureFailed)
        let sut = makeSUT(camera: camera)

        sut.capture()
        await sut.captureTask?.value

        #expect(sut.stage == .camera)
        #expect(sut.alertError == .captureFailed)
    }

    @Test func capturePhotoWriteFailurePersistsNothing() async {
        let camera = FakeCameraService()
        camera.permission = .granted
        let activeRepository = InMemoryActiveChallengeRepository()
        let photoRepository = SpyPhotoRepository()
        photoRepository.saveError = AppError.unexpected
        let sut = makeSUT(camera: camera, activeRepository: activeRepository, photoRepository: photoRepository)

        sut.capture()
        await sut.captureTask?.value

        #expect(activeRepository.stored == nil)
        #expect(sut.stage == .camera)
        #expect(sut.alertError == .captureFailed)
    }

    @Test func sessionStartFailureSetsCameraUnavailable() async {
        let camera = FakeCameraService()
        camera.permission = .granted
        camera.startError = AppError.cameraUnavailable
        let sut = makeSUT(camera: camera)

        sut.cameraAppeared()
        await sut.sessionTask?.value

        #expect(sut.alertError == .cameraUnavailable)
    }

    // MARK: Discard (editor X — the story-style retake)

    @Test func discardPhotoDeletesFileClearsDraftAndReturnsToCamera() {
        let camera = FakeCameraService()
        camera.permission = .granted
        var challenge = ActiveChallenge(card: ChallengeCard(prompt: "x"), acceptedAt: .distantPast)
        let photoID = UUID().uuidString
        challenge.photoID = photoID
        challenge.draft = EditDraft(texts: [TextItem(content: "hi")])
        let activeRepository = InMemoryActiveChallengeRepository()
        activeRepository.stored = challenge
        let photoRepository = SpyPhotoRepository()
        let sut = makeSUT(
            challenge: challenge,
            camera: camera,
            activeRepository: activeRepository,
            photoRepository: photoRepository
        )
        #expect(sut.stage == .editor)

        sut.discardPhoto()

        #expect(photoRepository.deleted == [photoID])
        #expect(activeRepository.stored?.photoID == nil)
        #expect(activeRepository.stored?.draft.isEmpty == true)
        #expect(sut.stage == .camera)
    }

    // MARK: Completion (FR-012/029/030)

    private func makeEditorStageSUT(
        activeRepository: InMemoryActiveChallengeRepository = InMemoryActiveChallengeRepository(),
        completedRepository: InMemoryCompletedChallengeRepository = InMemoryCompletedChallengeRepository()
    ) -> CaptureFlowViewModel {
        var challenge = ActiveChallenge(card: ChallengeCard(prompt: "x"), acceptedAt: .distantPast)
        challenge.photoID = UUID().uuidString
        activeRepository.stored = challenge
        let camera = FakeCameraService()
        camera.permission = .granted
        return makeSUT(
            challenge: challenge,
            camera: camera,
            activeRepository: activeRepository,
            completedRepository: completedRepository
        )
    }

    @Test func completeChallengeRecordsCompletionAndClearsActiveChallenge() {
        let activeRepository = InMemoryActiveChallengeRepository()
        let completedRepository = InMemoryCompletedChallengeRepository()
        let sut = makeEditorStageSUT(activeRepository: activeRepository, completedRepository: completedRepository)

        sut.completeChallenge()

        #expect(completedRepository.stored.count == 1)
        #expect(completedRepository.stored[0].card.prompt == "x")
        #expect(activeRepository.stored == nil)
        #expect(sut.isCompleted)
    }

    @Test func completeChallengeIsIdempotent() {
        let completedRepository = InMemoryCompletedChallengeRepository()
        let sut = makeEditorStageSUT(completedRepository: completedRepository)

        sut.completeChallenge()
        sut.completeChallenge()

        #expect(completedRepository.stored.count == 1)
    }

    @Test func completeChallengeWithoutPhotoRecordsNothing() {
        let completedRepository = InMemoryCompletedChallengeRepository()
        let sut = makeSUT(completedRepository: completedRepository)

        sut.completeChallenge()

        #expect(completedRepository.stored.isEmpty)
        #expect(!sut.isCompleted)
    }
}
