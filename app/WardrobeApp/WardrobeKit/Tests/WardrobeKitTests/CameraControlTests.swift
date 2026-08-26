import CoreGraphics
import Foundation
import Testing
@testable import WardrobeKit

/// Camera framing controls and gallery import, split out of
/// `CaptureFlowViewModelTests` to keep each suite focused.
@MainActor
struct CameraControlTests {
    private func makeSUT(
        challenge: ActiveChallenge = ActiveChallenge(card: ChallengeCard(prompt: "x"), acceptedAt: .distantPast),
        camera: FakeCameraService = FakeCameraService(),
        activeRepository: InMemoryActiveChallengeRepository = InMemoryActiveChallengeRepository(),
        photoRepository: SpyPhotoRepository = SpyPhotoRepository(),
        library: FakePhotoLibrary = FakePhotoLibrary()
    ) -> CaptureFlowViewModel {
        CaptureFlowViewModel(
            challenge: challenge,
            camera: camera,
            activeRepository: activeRepository,
            completedRepository: InMemoryCompletedChallengeRepository(),
            photoRepository: photoRepository,
            previews: InMemoryCompletionPreviewRepository(),
            library: library,
            scanner: FakeGarmentScanService(),
            wardrobeRepository: InMemoryWardrobeItemRepository(),
            thumbnails: InMemoryGarmentThumbnailRepository(),
            preferences: InMemoryAccountPreferencesRepository(),
            outbox: StoredOutboxRepository(store: InMemoryOutboxStore()),
            uploads: makeInMemoryUploads()
        )
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

    @Test func setDisplayZoomMirrorsClampedServiceValue() async {
        let camera = FakeCameraService()
        camera.permission = .granted
        let sut = makeSUT(camera: camera)
        sut.cameraAppeared()
        await sut.sessionTask?.value
        sut.flipCamera() // the ultra-wide floor only exists on the back camera
        await sut.flipTask?.value

        sut.setDisplayZoom(0.5)
        #expect(sut.displayZoomFactor == 0.5)
        #expect(camera.displayZoomFactor == 0.5)

        sut.setDisplayZoom(99) // clamped to the widest preset
        #expect(sut.displayZoomFactor == 2)

        sut.setDisplayZoom(0.1) // clamped to the ultra-wide floor
        #expect(sut.displayZoomFactor == 0.5)
    }

    @Test func theChallengeCameraOpensFacingTheUser() async {
        let camera = FakeCameraService()
        camera.permission = .granted
        let sut = makeSUT(camera: camera)

        sut.cameraAppeared()
        await sut.sessionTask?.value

        #expect(sut.isUsingFrontCamera, "an outfit photo is taken of the person holding the phone")
    }

    @Test func reopeningTheChallengeCameraReturnsToTheFront() async {
        let camera = FakeCameraService()
        camera.permission = .granted
        let sut = makeSUT(camera: camera)
        sut.cameraAppeared()
        await sut.sessionTask?.value
        sut.flipCamera()
        await sut.flipTask?.value
        #expect(!sut.isUsingFrontCamera)

        sut.cameraDisappeared()
        sut.cameraAppeared()
        await sut.sessionTask?.value

        #expect(sut.isUsingFrontCamera, "the flip lasts for that session only; opening the screen asks again")
    }

    @Test func backCameraOffersUltraWidePresetAndFrontDoesNot() async {
        let camera = FakeCameraService()
        camera.permission = .granted
        let sut = makeSUT(camera: camera)
        sut.cameraAppeared()
        await sut.sessionTask?.value
        #expect(sut.isUsingFrontCamera, "the challenge camera opens facing the user")
        #expect(sut.zoomOptions == [1, 2])

        sut.flipCamera()
        await sut.flipTask?.value

        #expect(!sut.isUsingFrontCamera)
        #expect(sut.zoomOptions == [0.5, 1, 2])
        #expect(sut.displayZoomFactor == CameraZoom.standard) // new lens starts at 1x
    }

    @Test func toggleFrontZoomAlternatesBetweenTheTwoFramings() async {
        let camera = FakeCameraService()
        camera.permission = .granted
        let sut = makeSUT(camera: camera)
        sut.cameraAppeared()
        await sut.sessionTask?.value
        #expect(sut.zoomOptions == [1, 2])

        sut.toggleFrontZoom()
        #expect(sut.displayZoomFactor == 2)

        sut.toggleFrontZoom()
        #expect(sut.displayZoomFactor == 1)
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

    // MARK: Gallery import (PRD open question #6)

    @Test func usePickedPhotoPersistsThenOpensCrop() async throws {
        let camera = FakeCameraService()
        camera.permission = .granted
        let activeRepository = InMemoryActiveChallengeRepository()
        let photoRepository = SpyPhotoRepository()
        let sut = makeSUT(camera: camera, activeRepository: activeRepository, photoRepository: photoRepository)
        let picked = try SampleCameraService.makeSampleJPEG(width: 60, height: 60)

        sut.usePickedPhoto(picked)
        await sut.importTask?.value

        let savedID = photoRepository.saved.keys.first
        #expect(photoRepository.saved.values.first == picked)
        #expect(activeRepository.stored?.photoID == savedID)
        #expect(sut.stage == .crop)
    }

    @Test func usePickedPhotoRejectsUndecodableDataAndPersistsNothing() async {
        let camera = FakeCameraService()
        camera.permission = .granted
        let activeRepository = InMemoryActiveChallengeRepository()
        let photoRepository = SpyPhotoRepository()
        let sut = makeSUT(camera: camera, activeRepository: activeRepository, photoRepository: photoRepository)

        sut.usePickedPhoto(Data("not an image".utf8))
        await sut.importTask?.value

        #expect(photoRepository.saved.isEmpty)
        #expect(activeRepository.stored == nil)
        #expect(sut.stage == .camera)
        #expect(sut.alertError == .photoImportFailed)
    }

    // MARK: Library access on camera open

    @Test func prepareLibraryAccessPromptsOnceThenLoadsGallery() async throws {
        let camera = FakeCameraService()
        camera.permission = .granted
        let jpeg = try SampleCameraService.makeSampleJPEG(width: 40, height: 40)
        let library = FakePhotoLibrary(
            access: .notDetermined,
            accessAfterRequest: .authorized,
            assets: [PhotoAsset(id: "a"), PhotoAsset(id: "b")],
            thumbnail: ImageDecoding.downsampledImage(from: jpeg, maxPixel: 40)
        )
        let sut = makeSUT(camera: camera, library: library)

        sut.prepareLibraryAccess()
        await sut.thumbnailTask?.value

        #expect(await library.requestAccessCount == 1)
        #expect(sut.libraryAccess == .authorized)
        #expect(sut.recentAssets.map(\.id) == ["a", "b"])
        #expect(sut.galleryThumbnail != nil)
    }

    @Test func prepareLibraryAccessDoesNotPromptWhenAlreadyDecided() async {
        let camera = FakeCameraService()
        camera.permission = .granted
        let library = FakePhotoLibrary(access: .authorized, assets: [PhotoAsset(id: "a")])
        let sut = makeSUT(camera: camera, library: library)

        sut.prepareLibraryAccess()
        await sut.thumbnailTask?.value

        #expect(await library.requestAccessCount == 0)
        #expect(sut.recentAssets.count == 1)
    }

    @Test func deniedLibraryLeavesGalleryEmptyWithoutError() async {
        let camera = FakeCameraService()
        camera.permission = .granted
        let library = FakePhotoLibrary(
            access: .notDetermined,
            accessAfterRequest: .denied,
            assets: [PhotoAsset(id: "a")]
        )
        let sut = makeSUT(camera: camera, library: library)

        sut.prepareLibraryAccess()
        await sut.thumbnailTask?.value

        #expect(sut.libraryAccess == .denied)
        #expect(sut.recentAssets.isEmpty)
        #expect(sut.galleryThumbnail == nil)
        #expect(sut.alertError == nil) // no access is not an error
    }

    // MARK: Tap-to-import from the in-app grid

    @Test func importAssetUsesTheTappedPhotoImmediately() async throws {
        let camera = FakeCameraService()
        camera.permission = .granted
        let picked = try SampleCameraService.makeSampleJPEG(width: 60, height: 60)
        let library = FakePhotoLibrary(access: .authorized, assets: [PhotoAsset(id: "a")], data: picked)
        let activeRepository = InMemoryActiveChallengeRepository()
        let photoRepository = SpyPhotoRepository()
        let sut = makeSUT(camera: camera, activeRepository: activeRepository, photoRepository: photoRepository, library: library)
        sut.isGalleryPresented = true

        sut.importAsset(id: "a")
        await sut.importTask?.value

        #expect(photoRepository.saved.values.first == picked)
        #expect(activeRepository.stored?.photoID == photoRepository.saved.keys.first)
        #expect(sut.stage == .crop)
        #expect(!sut.isGalleryPresented)
    }

    @Test func importAssetWithoutDataReportsFailureAndPersistsNothing() async {
        let camera = FakeCameraService()
        camera.permission = .granted
        let library = FakePhotoLibrary(access: .authorized, assets: [PhotoAsset(id: "a")]) // no data
        let activeRepository = InMemoryActiveChallengeRepository()
        let photoRepository = SpyPhotoRepository()
        let sut = makeSUT(camera: camera, activeRepository: activeRepository, photoRepository: photoRepository, library: library)

        sut.importAsset(id: "a")
        await sut.importTask?.value

        #expect(photoRepository.saved.isEmpty)
        #expect(activeRepository.stored == nil)
        #expect(sut.stage == .camera)
        #expect(sut.alertError == .photoImportFailed)
    }
}
