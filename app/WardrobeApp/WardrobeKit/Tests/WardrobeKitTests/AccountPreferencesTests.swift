import Foundation
import Testing
@testable import WardrobeKit

/// FR-002 and FR-099: the handful of conveniences that follow the account
/// rather than the phone.
struct AccountPreferencesTests {
    private func makeDefaults(_ name: String) throws -> UserDefaults {
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    // MARK: Recents

    @Test func rememberingPutsTheNewestFirst() {
        var preferences = AccountPreferences()

        preferences.remember(stickerID: "a")
        preferences.remember(stickerID: "b")

        #expect(preferences.recentStickerIDs == ["b", "a"])
    }

    @Test func rememberingTheSameStickerMovesItRatherThanRepeatingIt() {
        var preferences = AccountPreferences(recentStickerIDs: ["a", "b", "c"])

        preferences.remember(stickerID: "c")

        #expect(preferences.recentStickerIDs == ["c", "a", "b"])
    }

    @Test func theListIsCappedSoTheRowStaysSmallWhenItSyncs() {
        var preferences = AccountPreferences()

        for index in 0 ..< (AccountPreferences.recentStickerLimit + 10) {
            preferences.remember(stickerID: "id-\(index)")
        }

        #expect(preferences.recentStickerIDs.count == AccountPreferences.recentStickerLimit)
        #expect(preferences.recentStickerIDs.first == "id-\(AccountPreferences.recentStickerLimit + 9)")
    }

    /// A shrinking catalogue must never leave holes in the row.
    @Test func idsTheCatalogueNoLongerShipsAreSkippedOnRead() {
        let preferences = AccountPreferences(
            recentStickerIDs: ["sticker.retired", "emoji.fire", "nonsense"]
        )

        #expect(preferences.knownRecentStickerIDs == ["emoji.fire"])
    }

    // MARK: Storage

    @Test func preferencesSurviveARoundTrip() throws {
        let defaults = try makeDefaults("AccountPreferencesTests.roundTrip")
        let repository = UserDefaultsAccountPreferencesRepository(defaults: defaults)

        repository.save(AccountPreferences(recentStickerIDs: ["emoji.fire"], hasCompletedOnboarding: true))

        let restored = repository.load()
        #expect(restored.recentStickerIDs == ["emoji.fire"])
        #expect(restored.hasCompletedOnboarding)
    }

    @Test func fieldsAddedLaterDefaultRatherThanFail() throws {
        let json = Data(#"{"recentStickerIDs":["emoji.fire"]}"#.utf8)

        let preferences = try JSONDecoder().decode(AccountPreferences.self, from: json)

        #expect(preferences.hasCompletedOnboarding == false)
    }

    /// Onboarding used to live in its own key. Missing this read would walk
    /// every existing user back through onboarding on update.
    @Test func theOldOnboardingFlagIsReadWhenNoRecordExistsYet() throws {
        let defaults = try makeDefaults("AccountPreferencesTests.legacy")
        defaults.set(true, forKey: "hasCompletedOnboarding")

        let preferences = UserDefaultsAccountPreferencesRepository(defaults: defaults).load()

        #expect(preferences.hasCompletedOnboarding)
    }

    @Test func aFreshInstallHasNotCompletedOnboarding() throws {
        let defaults = try makeDefaults("AccountPreferencesTests.fresh")

        #expect(!UserDefaultsAccountPreferencesRepository(defaults: defaults).load().hasCompletedOnboarding)
    }
}
