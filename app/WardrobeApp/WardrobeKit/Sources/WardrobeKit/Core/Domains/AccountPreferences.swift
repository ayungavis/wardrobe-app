import Foundation

public struct AccountPreferences: Equatable, Codable, Sendable {
    public var recentStickerIDs: [String]
    public var onboardingCompletedAt: Date?
    public var uploadConsentAt: Date?
    public var uploadConsentDeclinedAt: Date?
    public var hasSeenCaptureTips: Bool

    public var hasCompletedOnboarding: Bool {
        onboardingCompletedAt != nil
    }

    public static let recentStickerLimit = 12

    public init(
        recentStickerIDs: [String] = [],
        onboardingCompletedAt: Date? = nil,
        uploadConsentAt: Date? = nil,
        uploadConsentDeclinedAt: Date? = nil,
        hasSeenCaptureTips: Bool = false
    ) {
        self.recentStickerIDs = recentStickerIDs
        self.onboardingCompletedAt = onboardingCompletedAt
        self.uploadConsentAt = uploadConsentAt
        self.uploadConsentDeclinedAt = uploadConsentDeclinedAt
        self.hasSeenCaptureTips = hasSeenCaptureTips
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        recentStickerIDs = try container.decodeIfPresent([String].self, forKey: .recentStickerIDs) ?? []
        // ponytail: a blob written before onboardingCompletedAt existed carries
        // only the Bool. A true one is stamped .distantPast rather than "now" so a
        // reinstall cannot present an old completion as today's.
        if let stamped = try container.decodeIfPresent(Date.self, forKey: .onboardingCompletedAt) {
            onboardingCompletedAt = stamped
        } else {
            let legacy = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? false
            onboardingCompletedAt = legacy ? .distantPast : nil
        }
        uploadConsentAt = try container.decodeIfPresent(Date.self, forKey: .uploadConsentAt)
        uploadConsentDeclinedAt = try container.decodeIfPresent(Date.self, forKey: .uploadConsentDeclinedAt)
        hasSeenCaptureTips = try container.decodeIfPresent(Bool.self, forKey: .hasSeenCaptureTips) ?? false
    }

    // ponytail: hasSeenCaptureTips is deliberately absent — the server has no
    // field for it, so it stays this device's business.
    public struct Syncable: Equatable, Sendable {
        public let stickers: [String]
        public let onboarding: Date?
        public let consent: Date?
    }

    public var syncable: Syncable {
        Syncable(stickers: recentStickerIDs, onboarding: onboardingCompletedAt, consent: uploadConsentAt)
    }

    public mutating func remember(stickerID id: String) {
        recentStickerIDs.removeAll { $0 == id }
        recentStickerIDs.insert(id, at: 0)
        recentStickerIDs = Array(recentStickerIDs.prefix(Self.recentStickerLimit))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(recentStickerIDs, forKey: .recentStickerIDs)
        try container.encodeIfPresent(onboardingCompletedAt, forKey: .onboardingCompletedAt)
        try container.encodeIfPresent(uploadConsentAt, forKey: .uploadConsentAt)
        try container.encodeIfPresent(uploadConsentDeclinedAt, forKey: .uploadConsentDeclinedAt)
        try container.encode(hasSeenCaptureTips, forKey: .hasSeenCaptureTips)
    }

    private enum CodingKeys: String, CodingKey {
        case recentStickerIDs
        case onboardingCompletedAt
        case uploadConsentAt
        case uploadConsentDeclinedAt
        case hasCompletedOnboarding
        case hasSeenCaptureTips
    }

    public var knownRecentStickerIDs: [String] {
        recentStickerIDs.filter { StickerCatalogue.entry(id: $0) != nil }
    }
}
