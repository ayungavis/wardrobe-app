import Foundation
import Observation

@MainActor
@Observable
public final class OnboardingModel {
    public private(set) var isCompleted: Bool

    private let preferences: AccountPreferencesRepository
    private let accounts: AppleAccountRepository
    private let session: SessionService

    public init(
        preferences: AccountPreferencesRepository,
        accounts: AppleAccountRepository,
        session: SessionService
    ) {
        self.preferences = preferences
        self.accounts = accounts
        self.session = session
        isCompleted = preferences.load().hasCompletedOnboarding
    }

    var isSignedIn: Bool {
        accounts.load() != nil
    }

    func signIn(identityToken: String, nonce: String, profile: AppleProfile) async throws {
        let accountID = try await session.linkApple(identityToken: identityToken, nonce: nonce)
        try accounts.save(
            AppleAccount(accountID: accountID, fullName: profile.fullName, email: profile.email)
        )
        setCompleted(true)
    }

    func skip() {
        setCompleted(true)
    }

    func reset() async throws {
        try accounts.clear()
        try await session.signOut()
        setCompleted(false)
    }

    private func setCompleted(_ completed: Bool) {
        var stored = preferences.load()
        stored.onboardingCompletedAt = completed ? (stored.onboardingCompletedAt ?? Date()) : nil
        preferences.save(stored)
        isCompleted = completed
    }
}
