import Foundation

/// A challenge the user committed with the checkmark (PRD FR-028).
///
/// Wear records and confirmed wardrobe items (FR-029) arrive with the AI
/// review step; this record is the part that exists today, and it keeps the
/// photo + edits so History can render the outfit later.
public struct CompletedChallenge: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let card: ChallengeCard
    public let photoID: String
    public let draft: EditDraft
    public let completedAt: Date

    public init(
        id: UUID = UUID(),
        card: ChallengeCard,
        photoID: String,
        draft: EditDraft,
        completedAt: Date
    ) {
        self.id = id
        self.card = card
        self.photoID = photoID
        self.draft = draft
        self.completedAt = completedAt
    }
}
