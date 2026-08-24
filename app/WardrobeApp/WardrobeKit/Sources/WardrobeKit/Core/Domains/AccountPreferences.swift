import Foundation

public struct AccountPreferences: Equatable, Codable, Sendable {
    public var recentStickerIDs: [String]
    public var hasCompletedOnboarding: Bool
    public var hasSeenCaptureTips: Bool

    public static let recentStickerLimit = 12

    public init(
        recentStickerIDs: [String] = [],
        hasCompletedOnboarding: Bool = false,
        hasSeenCaptureTips: Bool = false
    ) {
        self.recentStickerIDs = recentStickerIDs
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.hasSeenCaptureTips = hasSeenCaptureTips
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        recentStickerIDs = try container.decodeIfPresent([String].self, forKey: .recentStickerIDs) ?? []
        hasCompletedOnboarding = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? false
        hasSeenCaptureTips = try container.decodeIfPresent(Bool.self, forKey: .hasSeenCaptureTips) ?? false
    }

    public mutating func remember(stickerID id: String) {
        recentStickerIDs.removeAll { $0 == id }
        recentStickerIDs.insert(id, at: 0)
        recentStickerIDs = Array(recentStickerIDs.prefix(Self.recentStickerLimit))
    }

    public var knownRecentStickerIDs: [String] {
        recentStickerIDs.filter { StickerCatalogue.entry(id: $0) != nil }
    }
}
