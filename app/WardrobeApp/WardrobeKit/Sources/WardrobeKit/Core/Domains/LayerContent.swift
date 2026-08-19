import CoreGraphics
import Foundation

public enum LayerContent: Equatable, Sendable {
    case photo(PhotoContent)
    case text(TextContent)
    case sticker(StickerContent)
    case drawing(DrawingContent)
}

extension LayerContent: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, value
    }

    private enum Kind: String, Codable {
        case photo, text, sticker, drawing
    }

    private var kind: Kind {
        switch self {
        case .photo: .photo
        case .text: .text
        case .sticker: .sticker
        case .drawing: .drawing
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // An unrecognised kind means the document knows something this build
        // does not; say that, rather than surfacing a raw decoding error
        // (FR-098).
        guard let kind = try? container.decode(Kind.self, forKey: .kind) else {
            throw AppError.documentFromNewerApp
        }

        switch kind {
        case .photo: self = try .photo(container.decode(PhotoContent.self, forKey: .value))
        case .text: self = try .text(container.decode(TextContent.self, forKey: .value))
        case .sticker: self = try .sticker(container.decode(StickerContent.self, forKey: .value))
        case .drawing: self = try .drawing(container.decode(DrawingContent.self, forKey: .value))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)

        switch self {
        case let .photo(content): try container.encode(content, forKey: .value)
        case let .text(content): try container.encode(content, forKey: .value)
        case let .sticker(content): try container.encode(content, forKey: .value)
        case let .drawing(content): try container.encode(content, forKey: .value)
        }
    }
}

public struct PhotoContent: Equatable, Codable, Sendable {
    public let photoID: String
    public var crop: CropSpec?

    public init(photoID: String, crop: CropSpec? = nil) {
        self.photoID = photoID
        self.crop = crop
    }
}

public struct TextContent: Equatable, Codable, Sendable {
    public var content: String
    public var colorName: String
    public var backgroundStyleName: String
    public var fontName: String
    public var alignmentName: String

    public var textColor: TextColor {
        TextColor(rawValue: colorName) ?? .white
    }

    public var fontStyle: TextFontStyle {
        TextFontStyle(rawValue: fontName) ?? .classic
    }

    public var alignmentStyle: TextAlignmentStyle {
        TextAlignmentStyle(rawValue: alignmentName) ?? .center
    }

    public var backgroundStyle: TextBackgroundStyle {
        TextBackgroundStyle(rawValue: backgroundStyleName) ?? .none
    }

    public init(
        content: String,
        colorName: String = TextColor.white.rawValue,
        backgroundStyle: TextBackgroundStyle = .none,
        fontName: String = TextFontStyle.classic.rawValue,
        alignmentName: String = TextAlignmentStyle.center.rawValue
    ) {
        self.content = content
        self.colorName = colorName
        backgroundStyleName = backgroundStyle.rawValue
        self.fontName = fontName
        self.alignmentName = alignmentName
    }

    public init(_ item: TextItem) {
        self.init(
            content: item.content,
            colorName: item.colorName,
            backgroundStyle: item.hasBackground ? .solid : .none,
            fontName: item.fontName,
            alignmentName: item.alignmentName
        )
    }

    enum CodingKeys: String, CodingKey {
        case content, colorName, backgroundStyleName, fontName, alignmentName
        /// The two-state predecessor. Read forever, written never.
        case hasBackground
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        content = try container.decode(String.self, forKey: .content)
        colorName = try container.decodeIfPresent(String.self, forKey: .colorName) ?? TextColor.white.rawValue
        fontName = try container.decodeIfPresent(String.self, forKey: .fontName)
            ?? TextFontStyle.classic.rawValue
        alignmentName = try container.decodeIfPresent(String.self, forKey: .alignmentName)
            ?? TextAlignmentStyle.center.rawValue

        if let style = try container.decodeIfPresent(String.self, forKey: .backgroundStyleName) {
            backgroundStyleName = style
        } else {
            let hadBackground = try container.decodeIfPresent(Bool.self, forKey: .hasBackground) ?? false
            backgroundStyleName = (hadBackground ? TextBackgroundStyle.solid : .none).rawValue
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(content, forKey: .content)
        try container.encode(colorName, forKey: .colorName)
        try container.encode(backgroundStyleName, forKey: .backgroundStyleName)
        try container.encode(fontName, forKey: .fontName)
        try container.encode(alignmentName, forKey: .alignmentName)
    }
}

public struct StickerContent: Equatable, Sendable {
    public var art: StickerArt

    public init(art: StickerArt) {
        self.art = art
    }

    public init(emoji: String) {
        art = StickerArt(legacyEmoji: emoji)
    }
}

extension StickerContent: Codable {
    enum CodingKeys: String, CodingKey {
        case art
        /// The glyph-only predecessor. Read forever, written never.
        case emoji
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let art = try container.decodeIfPresent(StickerArt.self, forKey: .art) {
            self.art = art
        } else {
            art = try StickerArt(legacyEmoji: container.decode(String.self, forKey: .emoji))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(art, forKey: .art)
    }
}
