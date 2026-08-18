import Foundation

/// Convenience that follows the account rather than the phone (FR-002, FR-099):
/// onboarding does not replay on a second device, and sticker recents arrive
/// with it.
///
/// Deliberately one record rather than a key per preference — it is the unit
/// that will synchronize, and `docs/backend-schema.md` already decided that is
/// a narrow table keyed by account rather than columns bolted onto `account`.
public struct AccountPreferences: Equatable, Codable, Sendable {
    /// Most recent first, no duplicates. Ids, not glyphs, because half the
    /// catalogue has no glyph.
    public var recentStickerIDs: [String]
    public var hasCompletedOnboarding: Bool

    /// Long enough to hold a session's worth of choices, short enough that the
    /// row stays small when it starts syncing.
    public static let recentStickerLimit = 12

    public init(recentStickerIDs: [String] = [], hasCompletedOnboarding: Bool = false) {
        self.recentStickerIDs = recentStickerIDs
        self.hasCompletedOnboarding = hasCompletedOnboarding
    }

    /// Fields added later default rather than fail — a preference is never
    /// worth refusing to read the rest of the record over.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        recentStickerIDs = try container.decodeIfPresent([String].self, forKey: .recentStickerIDs) ?? []
        hasCompletedOnboarding = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? false
    }

    /// Moves `id` to the front, removing any earlier appearance, and trims to
    /// the limit.
    public mutating func remember(stickerID id: String) {
        recentStickerIDs.removeAll { $0 == id }
        recentStickerIDs.insert(id, at: 0)
        recentStickerIDs = Array(recentStickerIDs.prefix(Self.recentStickerLimit))
    }

    /// Ids the catalogue no longer knows are skipped rather than shown as gaps,
    /// so shrinking the catalogue can never break the row (FR-019: an
    /// unavailable asset does not block editing).
    public var knownRecentStickerIDs: [String] {
        recentStickerIDs.filter { StickerCatalogue.entry(id: $0) != nil }
    }
}
