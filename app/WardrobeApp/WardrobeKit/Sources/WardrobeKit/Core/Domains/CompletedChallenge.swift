import Foundation

public struct CompletedChallenge: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let card: ChallengeCard
    public let photoID: UUID
    public let document: EditorDocument
    public let completedAt: Date
    public var previewFile: String?
    public var syncQueuedAt: Date?

    public init(
        id: UUID = UUID(),
        card: ChallengeCard,
        photoID: UUID,
        document: EditorDocument,
        completedAt: Date,
        previewFile: String? = nil
    ) {
        self.id = id
        self.card = card
        self.photoID = photoID
        self.document = document
        self.completedAt = completedAt
        self.previewFile = previewFile
    }

    enum CodingKeys: String, CodingKey {
        case id, card, photoID, document, completedAt, previewFile
        case draft
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        card = try container.decode(ChallengeCard.self, forKey: .card)
        photoID = try container.decode(UUID.self, forKey: .photoID)
        completedAt = try container.decode(Date.self, forKey: .completedAt)
        previewFile = try container.decodeIfPresent(String.self, forKey: .previewFile)

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
        try container.encodeIfPresent(previewFile, forKey: .previewFile)
    }
}
