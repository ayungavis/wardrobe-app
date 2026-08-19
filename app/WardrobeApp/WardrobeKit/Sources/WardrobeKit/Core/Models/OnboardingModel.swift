import Foundation
import Observation

@MainActor
@Observable
public final class OnboardingModel {
    public private(set) var isCompleted: Bool

    private let preferences: AccountPreferencesRepository
    private let accounts: AppleAccountRepository

    public init(preferences: AccountPreferencesRepository, accounts: AppleAccountRepository) {
        self.preferences = preferences
        self.accounts = accounts
        isCompleted = preferences.load().hasCompletedOnboarding
    }

    var isSignedIn: Bool {
        accounts.load() != nil
    }

    func signIn(_ account: AppleAccount) throws {
        try accounts.save(account)
        setCompleted(true)
    }

    func skip() {
        setCompleted(true)
    }

    func reset() throws {
        try accounts.clear()
        setCompleted(false)
    }

    private func setCompleted(_ completed: Bool) {
        var stored = preferences.load()
        stored.hasCompletedOnboarding = completed
        preferences.save(stored)
        isCompleted = completed
    }
}
