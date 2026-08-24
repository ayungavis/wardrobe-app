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
