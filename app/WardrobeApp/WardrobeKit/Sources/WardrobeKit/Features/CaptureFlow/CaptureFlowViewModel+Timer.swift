import Foundation

// MARK: Self-timer (FR-016)

public extension CaptureFlowViewModel {
    func cycleTimer() {
        timer = timer.next
    }

    func cancelCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
        countdown = nil
    }

    func capture() {
        if countdown != nil {
            cancelCountdown()
            return
        }
        guard !isCapturing else { return }
        guard timer == .off else {
            startCountdown(seconds: timer.seconds)
            return
        }
        captureNow()
    }

    internal func startCountdown(seconds: Int) {
        countdownTask?.cancel()
        countdown = seconds
        countdownTask = Task {
            do {
                while let remaining = countdown, remaining > 0 {
                    try await sleep(.seconds(1))
                    try Task.checkCancellation()
                    countdown = remaining - 1
                }
                guard countdown != nil else { return }
                countdown = nil
                captureNow()
            } catch {
                countdown = nil
            }
        }
    }
}
