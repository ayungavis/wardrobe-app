import Foundation

/// What a sticker layer stores.
///
/// An identity rather than a glyph, because half the catalogue has no glyph —
/// the offline stickers are a symbol on a gradient tile. But a glyph stored
/// before the catalogue existed must keep rendering forever, including an emoji
/// no catalogue entry claims, so the two possibilities are one enum rather than
/// two optionals that could both be set or both be nil.
public enum StickerArt: Equatable, Sendable {
    /// A catalogue entry — emoji or gradient tile alike.
    case catalogue(String)
    /// A raw glyph from a document written before the catalogue. Permanent
    /// read path, never written again.
    case emoji(String)

    /// Reads a pre-catalogue glyph. A glyph the catalogue knows becomes that
    /// entry; anything else stays exactly the character the user picked.
    public init(legacyEmoji: String) {
        if let entry = StickerCatalogue.entry(matching: legacyEmoji) {
            self = .catalogue(entry.id)
        } else {
            self = .emoji(legacyEmoji)
        }
    }

    /// How to draw it. Nil only for a catalogue id this build has never heard
    /// of — FR-019 says an unavailable catalogue asset must not block editing,
    /// so the layer survives and the view draws a placeholder.
    public var design: StickerDesign? {
        switch self {
        case let .catalogue(id): StickerCatalogue.entry(id: id)?.design
        case let .emoji(glyph): .emoji(glyph)
        }
    }
}

extension StickerArt: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, value
    }

    private enum Kind: String, Codable {
        case catalogue, emoji
    }

    /// Hand-written for the same reason `LayerContent` is: the compiler names
    /// enum payloads `_0`, and a shape stored on people's phones cannot rest on
    /// a name the compiler may change.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // An unrecognised *kind* is a schema this build cannot read — unlike an
        // unrecognised catalogue *id*, which is just a picture we no longer
        // ship and which decodes fine.
        guard let kind = try? container.decode(Kind.self, forKey: .kind) else {
            throw AppError.documentFromNewerApp
        }

        switch kind {
        case .catalogue: self = try .catalogue(container.decode(String.self, forKey: .value))
        case .emoji: self = try .emoji(container.decode(String.self, forKey: .value))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .catalogue(id):
            try container.encode(Kind.catalogue, forKey: .kind)
            try container.encode(id, forKey: .value)
        case let .emoji(glyph):
            try container.encode(Kind.emoji, forKey: .kind)
            try container.encode(glyph, forKey: .value)
        }
    }
}
