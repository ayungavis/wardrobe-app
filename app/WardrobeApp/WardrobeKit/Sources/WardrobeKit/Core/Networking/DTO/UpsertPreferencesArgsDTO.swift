import Foundation

struct UpsertPreferencesArgsDTO: Encodable, Sendable, Equatable {
    var onboardingCompletedAt: Date?
    var recentStickerIds: [String]?
    var lastTextStyle: JSONValue?
}
