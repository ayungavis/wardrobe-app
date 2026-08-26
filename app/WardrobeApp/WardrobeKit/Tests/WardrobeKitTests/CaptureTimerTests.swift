import Testing
@testable import WardrobeKit

@MainActor
struct CaptureTimerTests {
    @Test func theTimerCyclesOffThreeFiveTenAndBackToOff() {
        let sut = makeCaptureFlowSUT()

        #expect(sut.timer == .off)
        sut.cycleTimer()
        #expect(sut.timer == .three)
        sut.cycleTimer()
        #expect(sut.timer == .five)
        sut.cycleTimer()
        #expect(sut.timer == .ten)
        sut.cycleTimer()
        #expect(sut.timer == .off, "the cycle has to return to off or the timer cannot be turned back off")
    }

    @Test func theShutterFiresOnlyAfterTheCountdownReachesZero() async {
        let camera = FakeCameraService()
        camera.permission = .granted
        let sut = makeCaptureFlowSUT(camera: camera)
        sut.cycleTimer()

        sut.capture()
        #expect(sut.countdown == 3, "an armed timer must open a countdown instead of firing")
        #expect(camera.captureCount == 0, "an armed timer must delay the shutter, not fire it")

        await sut.countdownTask?.value
        await sut.captureTask?.value

        #expect(camera.captureCount == 1)
        #expect(sut.countdown == nil)
    }

    @Test func tappingTheShutterDuringTheCountdownCancelsIt() async {
        let camera = FakeCameraService()
        camera.permission = .granted
        let sut = makeCaptureFlowSUT(camera: camera)
        sut.cycleTimer()

        sut.capture()
        sut.capture()

        await sut.countdownTask?.value
        await sut.captureTask?.value

        #expect(sut.countdown == nil)
        #expect(camera.captureCount == 0, "a cancelled countdown must not leave a shutter armed")
    }

    @Test func leavingTheCameraCancelsTheCountdown() async {
        let camera = FakeCameraService()
        camera.permission = .granted
        let sut = makeCaptureFlowSUT(camera: camera)
        sut.cycleTimer()

        sut.capture()
        sut.cameraDisappeared()

        await sut.countdownTask?.value
        await sut.captureTask?.value

        #expect(sut.countdown == nil)
        #expect(camera.captureCount == 0, "closing the camera must not fire the shutter afterwards")
    }
}
