import CoreGraphics
import Foundation

// The flat, pre-canvas edit shape. **Read forever, written never.**
//
// Nothing in the app produces these any more — `EditorDocument` replaced them
// in S2. They survive because challenges and completions written before that
// are still sitting on people's phones, and `ActiveChallenge.init(from:)` and
// `CompletedChallenge.init(from:)` decode the old `draft` key into them so
// that work keeps opening. Deleting them would delete that work.
//
// They live in their own file so the split is visible: everything here is a
// read path, and everything that used to sit alongside them — `CropSpec` and
// the text style palette — is live and moved out.

/// Non-destructive edit instructions (PRD FR-018, §18.5). The original photo
/// is never modified — rendering applies these on top at export time.
public struct EditDraft: Codable, Equatable, Sendable {
    public var crop: CropSpec?
    public var texts: [TextItem]
    public var stickers: [StickerItem]

    public init(crop: CropSpec? = nil, texts: [TextItem] = [], stickers: [StickerItem] = []) {
        self.crop = crop
        self.texts = texts
        self.stickers = stickers
    }

    /// Drafts persist across app updates — decode fields added later leniently.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        crop = try container.decodeIfPresent(CropSpec.self, forKey: .crop)
        texts = try container.decodeIfPresent([TextItem].self, forKey: .texts) ?? []
        stickers = try container.decodeIfPresent([StickerItem].self, forKey: .stickers) ?? []
    }

    public var isEmpty: Bool {
        crop == nil && texts.isEmpty && stickers.isEmpty
    }
}

public struct TextItem: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public var content: String
    /// Center position in unit image space (0...1).
    public var position: CGPoint
    public var scale: CGFloat
    public var rotationDegrees: Double
    public var colorName: String
    public var hasBackground: Bool
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

    public init(
        id: UUID = UUID(),
        content: String,
        position: CGPoint = CGPoint(x: 0.5, y: 0.5),
        scale: CGFloat = 1,
        rotationDegrees: Double = 0,
        colorName: String = TextColor.white.rawValue,
        hasBackground: Bool = false,
        fontName: String = TextFontStyle.classic.rawValue,
        alignmentName: String = TextAlignmentStyle.center.rawValue
    ) {
        self.id = id
        self.content = content
        self.position = position
        self.scale = scale
        self.rotationDegrees = rotationDegrees
        self.colorName = colorName
        self.hasBackground = hasBackground
        self.fontName = fontName
        self.alignmentName = alignmentName
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        content = try container.decode(String.self, forKey: .content)
        position = try container.decode(CGPoint.self, forKey: .position)
        scale = try container.decode(CGFloat.self, forKey: .scale)
        rotationDegrees = try container.decodeIfPresent(Double.self, forKey: .rotationDegrees) ?? 0
        colorName = try container.decodeIfPresent(String.self, forKey: .colorName) ?? TextColor.white.rawValue
        hasBackground = try container.decodeIfPresent(Bool.self, forKey: .hasBackground) ?? false
        fontName = try container.decodeIfPresent(String.self, forKey: .fontName) ?? TextFontStyle.classic.rawValue
        alignmentName = try container.decodeIfPresent(String.self, forKey: .alignmentName)
            ?? TextAlignmentStyle.center.rawValue
    }
}

/// Emoji sticker overlay (PRD FR-019 sticker set).
public struct StickerItem: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public var emoji: String
    /// Center position in unit image space (0...1).
    public var position: CGPoint
    public var scale: CGFloat
    public var rotationDegrees: Double

    public init(
        id: UUID = UUID(),
        emoji: String,
        position: CGPoint = CGPoint(x: 0.5, y: 0.5),
        scale: CGFloat = 1,
        rotationDegrees: Double = 0
    ) {
        self.id = id
        self.emoji = emoji
        self.position = position
        self.scale = scale
        self.rotationDegrees = rotationDegrees
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        emoji = try container.decode(String.self, forKey: .emoji)
        position = try container.decode(CGPoint.self, forKey: .position)
        scale = try container.decode(CGFloat.self, forKey: .scale)
        rotationDegrees = try container.decodeIfPresent(Double.self, forKey: .rotationDegrees) ?? 0
    }
}
