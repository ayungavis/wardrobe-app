import Foundation
import Observation

@MainActor
@Observable
public final class OnboardingViewModel {
    var step: OnboardingStep = .wardrobe
    public private(set) var isCompleted = false
    var isSkipConfirmationPresented = false
    public var alertError: AppError?

    private let accountRepository: AppleAccountRepository
    private let preferencesRepository: AccountPreferencesRepository

    public init(
        accountRepository: AppleAccountRepository,
        preferencesRepository: AccountPreferencesRepository
    ) {
        self.accountRepository = accountRepository
        self.preferencesRepository = preferencesRepository
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
        complete()
    }

    func signedIn(_ account: AppleAccount) {
        do {
            try accountRepository.save(account)
            complete()
        } catch {
            Log.report(error)
            alertError = .unexpected
        }
    }

    func signInFailed(_ error: Error) {
        Log.report(error)
    }

    private func complete() {
        var preferences = preferencesRepository.load()
        preferences.hasCompletedOnboarding = true
        preferencesRepository.save(preferences)
        isCompleted = true
    }
}
