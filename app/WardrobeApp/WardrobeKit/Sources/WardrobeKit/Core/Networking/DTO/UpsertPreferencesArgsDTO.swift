import Foundation

struct UpsertPreferencesArgsDTO: Encodable, Sendable, Equatable {
    var onboardingCompletedAt: Date?
    var uploadConsentAt: Date?
    var recentStickerIds: [String]?
    var lastTextStyle: JSONValue?
}
