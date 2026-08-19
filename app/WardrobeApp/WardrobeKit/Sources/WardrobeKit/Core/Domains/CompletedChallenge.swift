import Foundation

/// A challenge the user committed with the checkmark (PRD FR-028).
///
/// Wear records and confirmed wardrobe items (FR-029) arrive with the AI
/// review step; this record is the part that exists today, and it keeps the
/// photo + canvas so History can re-open the exact document later (FR-096).
public struct CompletedChallenge: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let card: ChallengeCard
    public let photoID: String
    /// The confirmed canvas document. Unlike the in-progress one this is what
    /// synchronizes after ✓ and what a re-edit reopens.
    public let document: EditorDocument
    public let completedAt: Date

    public init(
        id: UUID = UUID(),
        card: ChallengeCard,
        photoID: String,
        document: EditorDocument,
        completedAt: Date
    ) {
        self.id = id
        self.card = card
        self.photoID = photoID
        self.document = document
        self.completedAt = completedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, card, photoID, document, completedAt
        /// The flat pre-canvas shape. Read forever, written never.
        case draft
    }

    /// Completions are history — the one thing in the app that must never be
    /// rewritten or dropped — so the old flat shape keeps a permanent read
    /// path here too.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        card = try container.decode(ChallengeCard.self, forKey: .card)
        photoID = try container.decode(String.self, forKey: .photoID)
        completedAt = try container.decode(Date.self, forKey: .completedAt)

        if let document = try container.decodeIfPresent(EditorDocument.self, forKey: .document) {
            self.document = document
        } else {
            let draft = try container.decodeIfPresent(EditDraft.self, forKey: .draft) ?? EditDraft()
            document = EditorDocument(migrating: draft, photoID: photoID)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(card, forKey: .card)
        try container.encode(photoID, forKey: .photoID)
        try container.encode(document, forKey: .document)
        try container.encode(completedAt, forKey: .completedAt)
    }
}
