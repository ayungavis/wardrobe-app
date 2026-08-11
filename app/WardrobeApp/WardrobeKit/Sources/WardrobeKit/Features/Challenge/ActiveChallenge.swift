import Foundation

/// The single accepted-but-not-completed challenge (PRD FR-011/FR-017).
public struct ActiveChallenge: Codable, Equatable, Sendable {
    public let card: ChallengeCard
    public let acceptedAt: Date
    /// Set once the user taps "Use Photo"; refers to `PhotoStore`.
    public var photoID: String?
    public var draft: EditDraft

    public init(
        card: ChallengeCard,
        acceptedAt: Date,
        photoID: String? = nil,
        draft: EditDraft = EditDraft()
    ) {
        self.card = card
        self.acceptedAt = acceptedAt
        self.photoID = photoID
        self.draft = draft
    }

    /// True when abandoning would discard work (FR-017: confirm first).
    public var hasDraftWork: Bool {
        photoID != nil || !draft.isEmpty
    }
}

public protocol ActiveChallengeStore: Sendable {
    func load() -> ActiveChallenge?
    func save(_ challenge: ActiveChallenge)
    func clear()
}

// ponytail: UserDefaults JSON blob; migrate to SwiftData when completion/history lands.
public final class UserDefaultsActiveChallengeStore: ActiveChallengeStore, @unchecked Sendable {
    // @unchecked: UserDefaults is documented thread-safe.
    private let defaults: UserDefaults
    private static let key = "activeChallenge"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> ActiveChallenge? {
        guard let data = defaults.data(forKey: Self.key) else { return nil }
        return try? JSONDecoder().decode(ActiveChallenge.self, from: data)
    }

    public func save(_ challenge: ActiveChallenge) {
        guard let data = try? JSONEncoder().encode(challenge) else {
            Log.report(AppError.unexpected)
            return
        }
        defaults.set(data, forKey: Self.key)
    }

    public func clear() {
        defaults.removeObject(forKey: Self.key)
    }
}
