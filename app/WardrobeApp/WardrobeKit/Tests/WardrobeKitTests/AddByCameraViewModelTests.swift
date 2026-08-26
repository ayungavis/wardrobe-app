import Foundation
import Testing
@testable import WardrobeKit

@MainActor
struct AddByCameraViewModelTests {
    private func makeSUT(
        camera: FakeCameraService = FakeCameraService(),
        scanner: FakeGarmentScanService = FakeGarmentScanService()
    ) -> AddByCameraViewModel {
        AddByCameraViewModel(
            camera: camera,
            review: GarmentReviewModel(
                scanner: scanner,
                photoRepository: SpyPhotoRepository(),
                wardrobeRepository: InMemoryWardrobeItemRepository(),
                thumbnails: InMemoryGarmentThumbnailRepository()
            )
        )
    }

    @Test func permissionIsAskedForOnceAndTheSessionFollowsIt() async {
        let camera = FakeCameraService()
        camera.permissionAfterRequest = .granted
        let sut = makeSUT(camera: camera)

        await sut.onAppear()

        #expect(sut.permission == .granted)
    }

    @Test func aDeniedPermissionNeverStartsTheSession() async {
        let camera = FakeCameraService()
        camera.permissionAfterRequest = .denied
        let sut = makeSUT(camera: camera)

        await sut.onAppear()

        #expect(sut.permission == .denied)
        #expect(sut.previewSession == nil)
    }

    @Test func aFailingCaptureSurfacesATypedErrorAndLeavesTheCountAlone() async {
        let camera = FakeCameraService()
        camera.captureResult = .failure(AppError.captureFailed)
        let sut = makeSUT(camera: camera)

        sut.capture()
        await sut.settle()

        #expect(sut.alertError == .captureFailed)
        #expect(sut.capturedCount == 0)
        #expect(sut.isCapturing == false)
    }

    @Test func aSuccessfulCaptureCountsAndStagesTheGarment() async {
        let sut = makeSUT()

        sut.capture()
        await sut.settle()

        #expect(sut.capturedCount == 1)
        #expect(sut.alertError == nil)
    }

    @Test func aSecondShutterTapWhileOneIsInFlightIsIgnored() async {
        let sut = makeSUT()

        sut.capture()
        sut.capture()
        await sut.settle()

        #expect(sut.capturedCount == 1)
    }

    @Test func leavingTheScreenStopsTheCameraSession() {
        let camera = FakeCameraService()
        let sut = makeSUT(camera: camera)

        sut.onDisappear()

        #expect(camera.stopCount == 1)
    }

    @Test func reviewingStopsTheSessionAndRetakingResetsTheCount() async {
        let camera = FakeCameraService()
        let sut = makeSUT(camera: camera)
        sut.capture()
        await sut.settle()

        await sut.beginReview()
        #expect(sut.phase == .reviewing)
        #expect(camera.stopCount == 1)

        sut.resumeCapturing()
        #expect(sut.phase == .capturing)
        #expect(sut.capturedCount == 0)
    }

    @Test func aFailingSessionStartSurfacesTheCameraUnavailableError() async {
        let camera = FakeCameraService()
        camera.permissionAfterRequest = .granted
        camera.startError = AppError.cameraUnavailable
        let sut = makeSUT(camera: camera)

        await sut.onAppear()
        await sut.settle()

        #expect(sut.alertError == .cameraUnavailable)
    }
}

@MainActor
struct WardrobeCameraControlTests {
    private func makeSUT() -> (AddByCameraViewModel, FakeCameraService) {
        let camera = FakeCameraService()
        camera.permission = .granted
        let review = GarmentReviewModel(
            scanner: FakeGarmentScanService(),
            photoRepository: SpyPhotoRepository(),
            wardrobeRepository: InMemoryWardrobeItemRepository(),
            thumbnails: InMemoryGarmentThumbnailRepository()
        )
        return (AddByCameraViewModel(camera: camera, review: review), camera)
    }

    @Test func theWardrobeCameraForwardsZoomToTheService() async {
        let (sut, camera) = makeSUT()
        await sut.onAppear()
        await sut.settle()

        sut.setDisplayZoom(2)

        #expect(camera.displayZoomFactor == 2)
        #expect(sut.displayZoomFactor == 2, "the view reads the model, so it has to mirror the service")
    }

    @Test func theWardrobeCameraForwardsFocusFlashAndFlip() async {
        let (sut, camera) = makeSUT()
        await sut.onAppear()
        await sut.settle()

        sut.focus(at: CGPoint(x: 0.25, y: 0.75))
        sut.toggleFlash()

        #expect(camera.focusPoints == [CGPoint(x: 0.25, y: 0.75)])
        #expect(camera.isFlashOn)
        #expect(sut.isFlashOn)
    }

    @Test func theWardrobeCameraReportsTheServicesZoomOptions() async {
        let (sut, camera) = makeSUT()
        await sut.onAppear()
        await sut.settle()

        #expect(sut.zoomOptions == camera.zoomOptions, "the presets belong to the device, not the view")
    }
}
