import Foundation

public struct ActiveChallenge: Codable, Equatable, Sendable {
    public let card: ChallengeCard
    public let acceptedAt: Date
    public var photoID: String?
    public var document: EditorDocument
    public var importedPhotoIDs: [String] = []

    public init(
        card: ChallengeCard,
        acceptedAt: Date,
        photoID: String? = nil,
        document: EditorDocument = EditorDocument(layers: []),
        importedPhotoIDs: [String] = []
    ) {
        self.card = card
        self.acceptedAt = acceptedAt
        self.photoID = photoID
        self.document = document
        self.importedPhotoIDs = importedPhotoIDs
    }

    enum CodingKeys: String, CodingKey {
        case card, acceptedAt, photoID, document, importedPhotoIDs
        case draft
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        card = try container.decode(ChallengeCard.self, forKey: .card)
        acceptedAt = try container.decode(Date.self, forKey: .acceptedAt)
        photoID = try container.decodeIfPresent(String.self, forKey: .photoID)
        importedPhotoIDs = try container.decodeIfPresent([String].self, forKey: .importedPhotoIDs) ?? []

        if let document = try container.decodeIfPresent(EditorDocument.self, forKey: .document) {
            self.document = document
        } else {
            let draft = try container.decodeIfPresent(EditDraft.self, forKey: .draft) ?? EditDraft()
            document = EditorDocument(migrating: draft, photoID: photoID)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(card, forKey: .card)
        try container.encode(acceptedAt, forKey: .acceptedAt)
        try container.encodeIfPresent(photoID, forKey: .photoID)
        try container.encode(document, forKey: .document)
        try container.encode(importedPhotoIDs, forKey: .importedPhotoIDs)
    }

    public var hasDraftWork: Bool {
        photoID != nil || !document.layers.isEmpty
    }
}
