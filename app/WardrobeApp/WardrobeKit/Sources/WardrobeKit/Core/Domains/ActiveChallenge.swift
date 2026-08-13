import Foundation

/// The single accepted-but-not-completed challenge (PRD FR-011/FR-017).
public struct ActiveChallenge: Codable, Equatable, Sendable {
    public let card: ChallengeCard
    public let acceptedAt: Date
    /// Set once the user taps "Use Photo"; refers to `PhotoRepository`.
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
