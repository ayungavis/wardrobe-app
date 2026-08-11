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
        store: InMemoryActiveChallengeStore = InMemoryActiveChallengeStore(),
        photoStore: SpyPhotoStore = SpyPhotoStore(),
        libraryPreview: FakeLibraryPreview = FakeLibraryPreview()
    ) -> CaptureFlowViewModel {
        CaptureFlowViewModel(
            challenge: challenge,
            camera: camera,
            store: store,
            photoStore: photoStore,
            libraryPreview: libraryPreview
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

    @Test func setDisplayZoomMirrorsClampedServiceValue() {
        let camera = FakeCameraService()
        camera.permission = .granted
        let sut = makeSUT(camera: camera)

        sut.setDisplayZoom(0.5)
        #expect(sut.displayZoomFactor == 0.5)
        #expect(camera.displayZoomFactor == 0.5)

        sut.setDisplayZoom(99) // clamped to the widest preset
        #expect(sut.displayZoomFactor == 2)

        sut.setDisplayZoom(0.1) // clamped to the ultra-wide floor
        #expect(sut.displayZoomFactor == 0.5)
    }

    @Test func backCameraOffersUltraWidePresetAndFrontDoesNot() async {
        let camera = FakeCameraService()
        camera.permission = .granted
        let sut = makeSUT(camera: camera)
        #expect(sut.zoomOptions == [0.5, 1, 2])
        #expect(!sut.isUsingFrontCamera)

        sut.setDisplayZoom(2)
        sut.flipCamera()
        await sut.flipTask?.value

        #expect(sut.isUsingFrontCamera)
        #expect(sut.zoomOptions == [1, 2])
        #expect(sut.displayZoomFactor == CameraZoom.standard) // new lens starts at 1x
    }

    @Test func toggleFrontZoomAlternatesBetweenTheTwoFramings() async {
        let camera = FakeCameraService()
        camera.permission = .granted
        let sut = makeSUT(camera: camera)
        sut.flipCamera()
        await sut.flipTask?.value

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

    @Test func usePickedPhotoPersistsThenOpensEditor() async throws {
        let camera = FakeCameraService()
        camera.permission = .granted
        let store = InMemoryActiveChallengeStore()
        let photoStore = SpyPhotoStore()
        let sut = makeSUT(camera: camera, store: store, photoStore: photoStore)
        let picked = try SampleCameraService.makeSampleJPEG(width: 60, height: 60)

        sut.usePickedPhoto(picked)
        await sut.importTask?.value

        let savedID = photoStore.saved.keys.first
        #expect(photoStore.saved.values.first == picked)
        #expect(store.stored?.photoID == savedID)
        #expect(sut.stage == .editor)
    }

    @Test func usePickedPhotoRejectsUndecodableDataAndPersistsNothing() async {
        let camera = FakeCameraService()
        camera.permission = .granted
        let store = InMemoryActiveChallengeStore()
        let photoStore = SpyPhotoStore()
        let sut = makeSUT(camera: camera, store: store, photoStore: photoStore)

        sut.usePickedPhoto(Data("not an image".utf8))
        await sut.importTask?.value

        #expect(photoStore.saved.isEmpty)
        #expect(store.stored == nil)
        #expect(sut.stage == .camera)
        #expect(sut.alertError == .photoImportFailed)
    }

    @Test func galleryThumbnailLoadsWhenLibraryAllowsIt() async throws {
        let camera = FakeCameraService()
        camera.permission = .granted
        let libraryPreview = FakeLibraryPreview()
        let jpeg = try SampleCameraService.makeSampleJPEG(width: 40, height: 40)
        libraryPreview.thumbnail = ImageDecoding.downsampledImage(from: jpeg, maxPixel: 40)
        let sut = makeSUT(camera: camera, libraryPreview: libraryPreview)

        sut.loadGalleryThumbnail()
        await sut.thumbnailTask?.value

        #expect(sut.galleryThumbnail != nil)
    }

    @Test func galleryThumbnailStaysNilWhenLibraryDenied() async {
        let camera = FakeCameraService()
        camera.permission = .granted
        let sut = makeSUT(camera: camera, libraryPreview: FakeLibraryPreview()) // returns nil

        sut.loadGalleryThumbnail()
        await sut.thumbnailTask?.value

        #expect(sut.galleryThumbnail == nil)
        #expect(sut.alertError == nil) // a missing thumbnail is not an error
    }
}
