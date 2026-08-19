import Foundation
import Observation

@MainActor
@Observable
public final class OnboardingViewModel {
    var step: OnboardingStep = .wardrobe
    var isSkipConfirmationPresented = false
    public var alertError: AppError?

    private let onboarding: OnboardingModel

    public init(onboarding: OnboardingModel) {
        self.onboarding = onboarding
    }

    var canGoBack: Bool {
        step.previous != nil
    }

    var isLastStep: Bool {
        step.next == nil
    }

    func next() {
        guard let next = step.next else { return }
        step = next
    }

    func back() {
        guard let previous = step.previous else { return }
        step = previous
    }

    func skip() {
        isSkipConfirmationPresented = true
    }

    func confirmSkip() {
        isSkipConfirmationPresented = false
        onboarding.skip()
    }

    func signedIn(_ account: AppleAccount) {
        do {
            try onboarding.signIn(account)
        } catch {
            Log.report(error)
            alertError = .unexpected
        }
    }

    func signInFailed(_ error: Error) {
        Log.report(error)
    }
}
