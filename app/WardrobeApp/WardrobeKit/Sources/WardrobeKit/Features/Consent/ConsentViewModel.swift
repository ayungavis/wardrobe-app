import Foundation
import Observation

@MainActor
@Observable
public final class ConsentViewModel {
    public let providerName: String
    private let preferences: AccountPreferencesRepository

    public init(preferences: AccountPreferencesRepository, providerName: String) {
        self.preferences = preferences
        self.providerName = providerName
    }

    public func grant() {
        var stored = preferences.load()
        stored.uploadConsentAt = stored.uploadConsentAt ?? Date()
        preferences.save(stored)
        Log.ui.info("Upload consent granted")
    }

    public func decline() {
        var stored = preferences.load()
        stored.uploadConsentDeclinedAt = stored.uploadConsentDeclinedAt ?? Date()
        preferences.save(stored)
        Log.ui.info("Upload consent declined")
    }
}
