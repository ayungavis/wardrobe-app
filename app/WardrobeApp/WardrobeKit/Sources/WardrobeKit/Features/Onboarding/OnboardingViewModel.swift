import Foundation
import Observation

@MainActor
@Observable
public final class OnboardingViewModel {
    var step: OnboardingStep = .wardrobe
    var isSkipConfirmationPresented = false
    var isSigningIn = false
    public var alertError: AppError?

    private var pendingNonce: String?

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

    func beginSignIn() -> String {
        let nonce = SignInNonce.make()
        pendingNonce = nonce
        return SignInNonce.hashed(nonce)
    }

    func signedIn(identityToken: String, profile: AppleProfile) async {
        guard let nonce = pendingNonce else {
            alertError = .unexpected
            return
        }
        pendingNonce = nil
        isSigningIn = true
        defer { isSigningIn = false }

        do {
            try await onboarding.signIn(
                identityToken: identityToken, nonce: nonce, profile: profile
            )
        } catch {
            Log.report(error)
            alertError = AppError(wrapping: error)
        }
    }

    func signInFailed(_ error: Error) {
        pendingNonce = nil
        Log.report(error)
    }
}
