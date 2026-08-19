import Foundation

public protocol AccountPreferencesRepository: Sendable {
    func load() -> AccountPreferences
    func save(_ preferences: AccountPreferences)
}

// ponytail: UserDefaults JSON, local-first and nothing else. FR-099's sync
// clause waits for the account-preferences table, which `docs/backend-schema.md`
// has decided the shape of but not built.
public final class UserDefaultsAccountPreferencesRepository: AccountPreferencesRepository, @unchecked Sendable {
    private let defaults: UserDefaults
    private static let key = "accountPreferences"
    private static let legacyOnboardingKey = "hasCompletedOnboarding"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> AccountPreferences {
        guard let data = defaults.data(forKey: Self.key) else {
            return AccountPreferences(
                hasCompletedOnboarding: defaults.bool(forKey: Self.legacyOnboardingKey)
            )
        }

        do {
            return try JSONDecoder().decode(AccountPreferences.self, from: data)
        } catch {
            Log.report(error)
            return AccountPreferences()
        }
    }

    public func save(_ preferences: AccountPreferences) {
        guard let data = try? JSONEncoder().encode(preferences) else {
            Log.report(AppError.unexpected)
            return
        }
        defaults.set(data, forKey: Self.key)
    }
}
