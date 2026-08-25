import Foundation

@MainActor
public protocol AccountPreferencesRepository: Sendable {
    func load() -> AccountPreferences
    func save(_ preferences: AccountPreferences)
}

// ponytail: UserDefaults, so the outbox entry and the preference write are two
// steps rather than one transaction. FR-057's single-transaction clause needs
// this to move to SwiftData; it rides the same move challenge completions need.
@MainActor
public final class UserDefaultsAccountPreferencesRepository: AccountPreferencesRepository {
    private let defaults: UserDefaults
    private let outbox: (any OutboxRepository)?
    private static let key = "accountPreferences"
    private static let legacyOnboardingKey = "hasCompletedOnboarding"

    public init(defaults: UserDefaults = .standard, outbox: (any OutboxRepository)? = nil) {
        self.defaults = defaults
        self.outbox = outbox
    }

    public func load() -> AccountPreferences {
        guard let data = defaults.data(forKey: Self.key) else {
            return AccountPreferences(
                onboardingCompletedAt: defaults.bool(forKey: Self.legacyOnboardingKey) ? .distantPast : nil
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
        let previous = load()
        guard let data = try? JSONEncoder().encode(preferences) else {
            Log.report(AppError.unexpected)
            return
        }
        defaults.set(data, forKey: Self.key)

        guard previous.syncable != preferences.syncable else { return }
        enqueue(preferences)
    }

    private func enqueue(_ preferences: AccountPreferences) {
        guard let outbox else { return }
        do {
            let args = UpsertPreferencesArgsDTO(
                onboardingCompletedAt: preferences.onboardingCompletedAt,
                uploadConsentAt: preferences.uploadConsentAt,
                recentStickerIds: preferences.recentStickerIDs
            )
            try outbox.enqueueReplacing(SyncMutation.upsertPreferences(args).queued(), at: Date())
        } catch {
            Log.report(error)
        }
    }
}
