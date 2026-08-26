import Foundation

public enum StickerArt: Equatable, Sendable {
    case catalogue(String)
    case emoji(String)

    public init(legacyEmoji: String) {
        if let entry = StickerCatalogue.entry(matching: legacyEmoji) {
            self = .catalogue(entry.id)
        } else {
            self = .emoji(legacyEmoji)
        }
    }

    public static func item(_ itemID: UUID) -> StickerArt {
        .catalogue(itemPrefix + itemID.uuidString)
    }

    public var wardrobeItemID: UUID? {
        guard case let .catalogue(id) = self, id.hasPrefix(Self.itemPrefix) else { return nil }
        return UUID(uuidString: String(id.dropFirst(Self.itemPrefix.count)))
    }

    private static let itemPrefix = "item."

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

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
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
