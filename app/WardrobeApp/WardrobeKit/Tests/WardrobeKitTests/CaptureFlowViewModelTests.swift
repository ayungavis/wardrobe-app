import CoreGraphics
import Foundation
import Testing
@testable import WardrobeKit

@MainActor
struct CaptureFlowViewModelTests {
    // MARK: Initial stage (FR-013/014/017)

    @Test func initialStageIsConsentWhenNotDetermined() {
        let camera = FakeCameraService()
        camera.permission = .notDetermined
        #expect(makeCaptureFlowSUT(camera: camera).stage == .consent)
    }

    @Test func initialStageIsCameraWhenGranted() {
        let camera = FakeCameraService()
        camera.permission = .granted
        #expect(makeCaptureFlowSUT(camera: camera).stage == .camera)
    }

    @Test func initialStageIsDeniedWhenDeniedOrRestricted() {
        for permission in [CameraPermission.denied, .restricted] {
            let camera = FakeCameraService()
            camera.permission = permission
            #expect(makeCaptureFlowSUT(camera: camera).stage == .denied)
        }
    }

    /// FR-083: a capture that was never framed reopens the crop step rather
    /// than skipping past it.
    @Test func initialStageIsCropWhenThePhotoIsNotFramedYet() {
        var challenge = ActiveChallenge(card: ChallengeCard(prompt: "x"), acceptedAt: .distantPast)
        challenge.photoID = UUID.v7()
        #expect(makeCaptureFlowSUT(challenge: challenge).stage == .crop)
    }

    /// The crop on the photo layer is what says the step is done — no second flag.
    @Test func initialStageIsEditorOnceTheCropExists() {
        let photoID = UUID.v7()
        var challenge = ActiveChallenge(card: ChallengeCard(prompt: "x"), acceptedAt: .distantPast)
        challenge.photoID = photoID
        challenge.document = EditorDocument(
            photoID: photoID, crop: CropSpec(rect: CGRect(x: 0, y: 0, width: 1, height: 0.75))
        )
        #expect(makeCaptureFlowSUT(challenge: challenge).stage == .editor)
    }

    // MARK: Consent (FR-013)

    @Test func consentContinueGrantedGoesToCamera() async {
        let camera = FakeCameraService()
        camera.permissionAfterRequest = .granted
        let sut = makeCaptureFlowSUT(camera: camera)

        sut.consentContinue()
        await sut.consentTask?.value

        #expect(sut.stage == .camera)
    }

    @Test func consentContinueDeniedGoesToDenied() async {
        let camera = FakeCameraService()
        camera.permissionAfterRequest = .denied
        let sut = makeCaptureFlowSUT(camera: camera)

        sut.consentContinue()
        await sut.consentTask?.value

        #expect(sut.stage == .denied)
    }

    // MARK: Permission recheck (FR-014)

    @Test func recheckFlipsCameraToDeniedAfterRevocation() {
        let camera = FakeCameraService()
        camera.permission = .granted
        let sut = makeCaptureFlowSUT(camera: camera)
        #expect(sut.stage == .camera)

        camera.permission = .denied
        sut.recheckPermission()

        #expect(sut.stage == .denied)
    }

    @Test func recheckDoesNotTouchEditor() {
        let camera = FakeCameraService()
        camera.permission = .denied
        let photoID = UUID.v7()
        var challenge = ActiveChallenge(card: ChallengeCard(prompt: "x"), acceptedAt: .distantPast)
        challenge.photoID = photoID
        challenge.document = EditorDocument(
            photoID: photoID, crop: CropSpec(rect: CGRect(x: 0, y: 0, width: 1, height: 0.75))
        )
        let sut = makeCaptureFlowSUT(challenge: challenge, camera: camera)

        sut.recheckPermission()

        #expect(sut.stage == .editor)
    }

    // MARK: Capture — hands off to the crop step (FR-016)

    @Test func captureSuccessPersistsPhotoThenCrop() async {
        let camera = FakeCameraService()
        camera.permission = .granted
        let photo = Data([0xAB, 0xCD])
        camera.captureResult = .success(photo)
        let activeRepository = InMemoryActiveChallengeRepository()
        let photoRepository = SpyPhotoRepository()
        let sut = makeCaptureFlowSUT(camera: camera, activeRepository: activeRepository, photoRepository: photoRepository)

        sut.capture()
        await sut.captureTask?.value

        let savedID = photoRepository.saved.keys.first
        #expect(savedID != nil)
        #expect(photoRepository.saved.values.first == photo)
        #expect(activeRepository.stored?.photoID == savedID)
        #expect(sut.stage == .crop)
        #expect(!sut.isCapturing)
    }

    @Test func captureFailureStaysInCameraWithError() async {
        let camera = FakeCameraService()
        camera.permission = .granted
        camera.captureResult = .failure(AppError.captureFailed)
        let sut = makeCaptureFlowSUT(camera: camera)

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
        let sut = makeCaptureFlowSUT(camera: camera, activeRepository: activeRepository, photoRepository: photoRepository)

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
        let sut = makeCaptureFlowSUT(camera: camera)

        sut.cameraAppeared()
        await sut.sessionTask?.value

        #expect(sut.alertError == .cameraUnavailable)
    }

    // MARK: Discard (editor X — the story-style retake)

    @Test func discardPhotoDeletesFileClearsDraftAndReturnsToCamera() {
        let camera = FakeCameraService()
        camera.permission = .granted
        var challenge = ActiveChallenge(card: ChallengeCard(prompt: "x"), acceptedAt: .distantPast)
        let photoID = UUID.v7()
        challenge.photoID = photoID
        challenge.document = .fixture(
            photoID: photoID,
            crop: CropSpec(rect: CGRect(x: 0, y: 0, width: 1, height: 0.75)),
            texts: [TextItem(content: "hi")]
        )
        let activeRepository = InMemoryActiveChallengeRepository()
        activeRepository.stored = challenge
        let photoRepository = SpyPhotoRepository()
        let sut = makeCaptureFlowSUT(
            challenge: challenge,
            camera: camera,
            activeRepository: activeRepository,
            photoRepository: photoRepository
        )
        #expect(sut.stage == .editor)

        sut.discardPhoto()

        #expect(photoRepository.deleted == [photoID])
        #expect(activeRepository.stored?.photoID == nil)
        #expect(activeRepository.stored?.document.layers.isEmpty == true)
        #expect(sut.stage == .camera)
    }

    // MARK: Crop step (FR-083)

    /// Use Crop stores an instruction, not a second image: the original stays
    /// the only photo on disk, and the editor and exporter both read the document.
    @Test func useCropStoresTheFramingAndOpensTheEditor() {
        let photoID = UUID.v7()
        var challenge = ActiveChallenge(card: ChallengeCard(prompt: "x"), acceptedAt: .distantPast)
        challenge.photoID = photoID
        challenge.document = EditorDocument(photoID: photoID)
        let activeRepository = InMemoryActiveChallengeRepository()
        let photoRepository = SpyPhotoRepository()
        let sut = makeCaptureFlowSUT(
            challenge: challenge,
            activeRepository: activeRepository,
            photoRepository: photoRepository
        )
        let crop = CropSpec(rect: CGRect(x: 0.1, y: 0.2, width: 0.6, height: 0.45))

        sut.useCrop(crop)

        #expect(sut.stage == .editor)
        #expect(activeRepository.stored?.document.firstPhotoCrop == crop)
        #expect(photoRepository.saved.isEmpty, "cropping must not write a second photo")
    }

    /// Nothing to frame means nothing to store.
    @Test func useCropWithoutAPhotoDoesNothing() {
        let activeRepository = InMemoryActiveChallengeRepository()
        let sut = makeCaptureFlowSUT(activeRepository: activeRepository)

        sut.useCrop(CropSpec(rect: CGRect(x: 0, y: 0, width: 1, height: 0.75)))

        #expect(sut.stage != .editor)
        #expect(activeRepository.stored == nil)
    }

    /// Retake from the crop step is the same discard the editor uses, so the
    /// photo goes with it.
    @Test func retakeFromCropDeletesThePhotoAndReturnsToCamera() {
        var challenge = ActiveChallenge(card: ChallengeCard(prompt: "x"), acceptedAt: .distantPast)
        let photoID = UUID.v7()
        challenge.photoID = photoID
        let photoRepository = SpyPhotoRepository()
        let sut = makeCaptureFlowSUT(challenge: challenge, photoRepository: photoRepository)
        #expect(sut.stage == .crop)

        sut.discardPhoto()

        #expect(photoRepository.deleted == [photoID])
        #expect(sut.stage == .camera)
    }

    // MARK: Restored draft (§17)

    /// Landing straight in the editor can only mean the challenge came off disk
    /// with the crop already committed — which is exactly what the restored
    /// notice states, so no separate flag is persisted to say it twice.
    @Test func aChallengeThatArrivesMidEditIsMarkedRestored() {
        let photoID = UUID.v7()
        var challenge = ActiveChallenge(card: ChallengeCard(prompt: "x"), acceptedAt: .distantPast)
        challenge.photoID = photoID
        // The crop is stored on the photo layer, so the document has to have one
        // — setting it on an empty document is a no-op by design.
        challenge.document = EditorDocument(photoID: photoID)
        if let layerID = challenge.document.firstPhotoLayerID {
            challenge.document.setCrop(CropSpec(rect: CGRect(x: 0, y: 0, width: 1, height: 1)), ofLayer: layerID)
        }
        let camera = FakeCameraService()
        camera.permission = .granted

        let sut = makeCaptureFlowSUT(challenge: challenge, camera: camera)

        #expect(sut.stage == .editor)
        #expect(sut.didResumeDraft)
    }

    @Test func aFreshlyAcceptedChallengeIsNotRestored() {
        let camera = FakeCameraService()
        camera.permission = .granted

        let sut = makeCaptureFlowSUT(camera: camera)

        #expect(sut.stage == .camera)
        #expect(!sut.didResumeDraft)
    }

    /// A photo taken but never framed reopens the crop step, and that is not a
    /// restored draft either — the work has not reached the canvas yet.
    @Test func aPhotoWaitingToBeCroppedIsNotRestored() {
        var challenge = ActiveChallenge(card: ChallengeCard(prompt: "x"), acceptedAt: .distantPast)
        challenge.photoID = UUID.v7()
        let camera = FakeCameraService()
        camera.permission = .granted

        let sut = makeCaptureFlowSUT(challenge: challenge, camera: camera)

        #expect(sut.stage == .crop)
        #expect(!sut.didResumeDraft)
    }
}
