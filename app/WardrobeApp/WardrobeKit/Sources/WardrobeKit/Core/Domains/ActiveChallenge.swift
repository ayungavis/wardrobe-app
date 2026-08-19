import Foundation

/// The single accepted-but-not-completed challenge (PRD FR-011/FR-017).
public struct ActiveChallenge: Codable, Equatable, Sendable {
    public let card: ChallengeCard
    public let acceptedAt: Date
    /// Set once the user taps "Use Photo"; refers to `PhotoRepository`.
    public var photoID: String?
    /// The in-progress canvas. Device-only for its whole life — it is never
    /// uploaded, which is what keeps §18.3 true; only the confirmed document
    /// on a completion leaves the phone.
    public var document: EditorDocument
    /// Photos this session added to the canvas (FR-093). Kept because a photo
    /// added and then deleted leaves nothing in the document to name its file,
    /// and the file is the user's own picture.
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
        /// The flat pre-canvas shape. Read forever, written never.
        case draft
    }

    /// Reads either shape. Challenges written before the layered canvas stored
    /// a flat `draft`, and they are sitting on people's phones mid-challenge —
    /// so the old key is a permanent read path, not a temporary one.
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

    /// True when abandoning would discard work (FR-017: confirm first).
    public var hasDraftWork: Bool {
        photoID != nil || !document.layers.isEmpty
    }
}
