import Foundation
import Testing
@testable import WardrobeKit

@MainActor
struct CaptureFlowViewModelTests {
    private func makeSUT(
        challenge: ActiveChallenge = ActiveChallenge(card: ChallengeCard(prompt: "x"), acceptedAt: .distantPast),
        camera: FakeCameraService = FakeCameraService(),
        store: InMemoryActiveChallengeStore = InMemoryActiveChallengeStore(),
        photoStore: SpyPhotoStore = SpyPhotoStore()
    ) -> CaptureFlowViewModel {
        CaptureFlowViewModel(challenge: challenge, camera: camera, store: store, photoStore: photoStore)
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

    @Test func recheckDoesNotTouchPreviewOrEditor() {
        let camera = FakeCameraService()
        camera.permission = .granted
        let sut = makeSUT(camera: camera)
        sut.capture()

        camera.permission = .denied
        var challenge = ActiveChallenge(card: ChallengeCard(prompt: "x"), acceptedAt: .distantPast)
        challenge.photoID = UUID().uuidString
        let editorSUT = makeSUT(challenge: challenge, camera: camera)

        editorSUT.recheckPermission()
        #expect(editorSUT.stage == .editor)
    }

    // MARK: Capture (FR-016)

    @Test func captureSuccessGoesToPreview() async {
        let camera = FakeCameraService()
        camera.permission = .granted
        let photo = Data([0xAB, 0xCD])
        camera.captureResult = .success(photo)
        let sut = makeSUT(camera: camera)

        sut.capture()
        await sut.captureTask?.value

        #expect(sut.stage == .preview(photo))
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

    @Test func sessionStartFailureSetsCameraUnavailable() async {
        let camera = FakeCameraService()
        camera.permission = .granted
        camera.startError = AppError.cameraUnavailable
        let sut = makeSUT(camera: camera)

        sut.cameraAppeared()
        await sut.sessionTask?.value

        #expect(sut.alertError == .cameraUnavailable)
    }

    // MARK: Flip camera

    @Test func flipCameraTogglesService() async {
        let camera = FakeCameraService()
        camera.permission = .granted
        let sut = makeSUT(camera: camera)

        sut.flipCamera()
        await sut.flipTask?.value

        #expect(camera.toggleCount == 1)
    }

    @Test func flipCameraFailureIsNonFatal() async {
        let camera = FakeCameraService()
        camera.permission = .granted
        camera.toggleError = AppError.cameraUnavailable
        let sut = makeSUT(camera: camera)

        sut.flipCamera()
        await sut.flipTask?.value

        #expect(sut.stage == .camera) // stays usable on the current camera
        #expect(sut.alertError == nil)
    }

    // MARK: Use photo ordering (FR-016, §18.5)

    @Test func usePhotoWritesFileThenPersistsIDThenEditor() {
        let camera = FakeCameraService()
        camera.permission = .granted
        let store = InMemoryActiveChallengeStore()
        let photoStore = SpyPhotoStore()
        let sut = makeSUT(camera: camera, store: store, photoStore: photoStore)
        let photo = Data([0x01, 0x02])

        sut.usePhoto(photo)

        let savedID = photoStore.saved.keys.first
        #expect(savedID != nil)
        #expect(store.stored?.photoID == savedID)
        #expect(sut.stage == .editor)
    }

    @Test func usePhotoWriteFailurePersistsNothing() {
        let camera = FakeCameraService()
        camera.permission = .granted
        let store = InMemoryActiveChallengeStore()
        let photoStore = SpyPhotoStore()
        photoStore.saveError = AppError.unexpected
        let sut = makeSUT(camera: camera, store: store, photoStore: photoStore)

        sut.usePhoto(Data([0x01]))

        #expect(store.stored == nil)
        #expect(sut.stage == .camera) // never left the pre-photo stages
        #expect(sut.alertError == .captureFailed)
    }
}
