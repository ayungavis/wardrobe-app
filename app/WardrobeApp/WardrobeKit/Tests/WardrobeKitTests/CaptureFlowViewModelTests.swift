import CoreGraphics
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

    @Test func recheckDoesNotTouchEditor() {
        let camera = FakeCameraService()
        camera.permission = .denied
        var challenge = ActiveChallenge(card: ChallengeCard(prompt: "x"), acceptedAt: .distantPast)
        challenge.photoID = UUID().uuidString
        let sut = makeSUT(challenge: challenge, camera: camera)

        sut.recheckPermission()

        #expect(sut.stage == .editor)
    }

    // MARK: Flip camera & flash

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

    @Test func toggleFlashMirrorsServiceState() {
        let camera = FakeCameraService()
        camera.permission = .granted
        let sut = makeSUT(camera: camera)
        #expect(!sut.isFlashOn)

        sut.toggleFlash()

        #expect(camera.isFlashOn)
        #expect(sut.isFlashOn)
    }

    // MARK: Zoom & focus

    @Test func setZoomMirrorsClampedServiceValue() {
        let camera = FakeCameraService()
        camera.permission = .granted
        let sut = makeSUT(camera: camera)

        sut.setZoom(2.5)
        #expect(sut.zoomFactor == 2.5)

        sut.setZoom(99) // clamped by the service ceiling
        #expect(sut.zoomFactor == CameraZoom.maxFactor)
        #expect(camera.zoomFactor == CameraZoom.maxFactor)

        sut.setZoom(0.1) // clamped by the floor
        #expect(sut.zoomFactor == CameraZoom.minFactor)
    }

    @Test func focusForwardsPointToService() {
        let camera = FakeCameraService()
        camera.permission = .granted
        let sut = makeSUT(camera: camera)
        let point = CGPoint(x: 0.25, y: 0.75)

        sut.focus(at: point)

        #expect(camera.focusPoints == [point])
        #expect(sut.focusPoint == point)
    }

    // MARK: Capture — straight to editor (FR-016, story-style)

    @Test func captureSuccessPersistsPhotoThenEditor() async {
        let camera = FakeCameraService()
        camera.permission = .granted
        let photo = Data([0xAB, 0xCD])
        camera.captureResult = .success(photo)
        let store = InMemoryActiveChallengeStore()
        let photoStore = SpyPhotoStore()
        let sut = makeSUT(camera: camera, store: store, photoStore: photoStore)

        sut.capture()
        await sut.captureTask?.value

        let savedID = photoStore.saved.keys.first
        #expect(savedID != nil)
        #expect(photoStore.saved.values.first == photo)
        #expect(store.stored?.photoID == savedID)
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
        let store = InMemoryActiveChallengeStore()
        let photoStore = SpyPhotoStore()
        photoStore.saveError = AppError.unexpected
        let sut = makeSUT(camera: camera, store: store, photoStore: photoStore)

        sut.capture()
        await sut.captureTask?.value

        #expect(store.stored == nil)
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
        let store = InMemoryActiveChallengeStore()
        store.stored = challenge
        let photoStore = SpyPhotoStore()
        let sut = makeSUT(challenge: challenge, camera: camera, store: store, photoStore: photoStore)
        #expect(sut.stage == .editor)

        sut.discardPhoto()

        #expect(photoStore.deleted == [photoID])
        #expect(store.stored?.photoID == nil)
        #expect(store.stored?.draft.isEmpty == true)
        #expect(sut.stage == .camera)
    }
}
