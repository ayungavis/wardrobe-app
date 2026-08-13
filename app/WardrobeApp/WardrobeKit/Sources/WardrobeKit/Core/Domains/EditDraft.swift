import CoreGraphics
import Foundation
import SwiftUI

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

/// Visible rect in unit image space (all components 0...1).
public struct CropSpec: Codable, Equatable, Sendable {
    public var rect: CGRect

    public init(rect: CGRect) {
        self.rect = rect
    }
}

/// Story-style text color palette (content palette, not a UI token).
public enum TextColor: String, CaseIterable, Sendable {
    case white, black, red, orange, yellow, green, blue, pink

    public var color: Color {
        switch self {
        case .white: .white
        case .black: .black
        case .red: Color(red: 0.93, green: 0.23, blue: 0.23)
        case .orange: Color(red: 0.98, green: 0.58, blue: 0.13)
        case .yellow: Color(red: 0.99, green: 0.86, blue: 0.20)
        case .green: Color(red: 0.22, green: 0.79, blue: 0.42)
        case .blue: Color(red: 0.22, green: 0.51, blue: 0.96)
        case .pink: Color(red: 0.95, green: 0.36, blue: 0.65)
        }
    }

    /// Readable text color when this color is used as the pill background.
    public var contrastText: Color {
        switch self {
        case .white, .yellow: .black
        default: .white
        }
    }
}

/// Story-style typefaces, all built from system font designs — no font files
/// to license or ship.
public enum TextFontStyle: String, CaseIterable, Sendable {
    case classic, bold, rounded, serif, mono

    public var design: Font.Design {
        switch self {
        case .classic, .bold: .default
        case .rounded: .rounded
        case .serif: .serif
        case .mono: .monospaced
        }
    }

    public var weight: Font.Weight {
        self == .bold ? .black : .bold
    }

    /// Shown on the style chips.
    public var sampleLabel: String {
        switch self {
        case .classic: "Aa"
        case .bold: "Aa"
        case .rounded: "Aa"
        case .serif: "Aa"
        case .mono: "Aa"
        }
    }
}

public enum TextAlignmentStyle: String, CaseIterable, Sendable {
    case leading, center, trailing

    public var textAlignment: TextAlignment {
        switch self {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    public var frameAlignment: Alignment {
        switch self {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    public var symbolName: String {
        switch self {
        case .leading: "text.alignleft"
        case .center: "text.aligncenter"
        case .trailing: "text.alignright"
        }
    }

    /// Cycled by the toolbar button, the way story editors do it.
    public var next: TextAlignmentStyle {
        switch self {
        case .leading: .center
        case .center: .trailing
        case .trailing: .leading
        }
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
