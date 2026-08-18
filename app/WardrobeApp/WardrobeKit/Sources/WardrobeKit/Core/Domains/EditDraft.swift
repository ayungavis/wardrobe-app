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
///
/// Order is the swatch order on screen. Raw values are stored, so they never
/// change — only the list may grow.
public enum TextColor: String, CaseIterable, Sendable {
    case white, black, yellow, orange, red, pink, purple, blue, cyan, green

    public var color: Color {
        switch self {
        case .white: .white
        case .black: .black
        case .yellow: Color(red: 1, green: 0.86, blue: 0.08)
        case .orange: Color(red: 1, green: 0.48, blue: 0.05)
        case .red: Color(red: 0.96, green: 0.16, blue: 0.18)
        case .pink: Color(red: 1, green: 0.23, blue: 0.55)
        case .purple: Color(red: 0.57, green: 0.24, blue: 0.92)
        case .blue: Color(red: 0.12, green: 0.47, blue: 0.98)
        case .cyan: Color(red: 0.08, green: 0.78, blue: 0.94)
        case .green: Color(red: 0.18, green: 0.78, blue: 0.35)
        }
    }

    /// Readable text color when this color is used as the pill background.
    public var contrastText: Color {
        switch self {
        case .black, .red, .purple, .blue: .white
        case .white, .yellow, .orange, .pink, .cyan, .green: .black
        }
    }

    public var name: String {
        String(localized: String.LocalizationValue(Self.nameKey(for: self)), bundle: .module)
    }

    /// Assembled at runtime, so the extractor never sees these keys in source
    /// and prunes them as stale. They are pinned `"extractionState": "manual"`
    /// in `Localizable.xcstrings`; a test fails if that pin is removed.
    static func nameKey(for color: TextColor) -> String {
        "editor.color.\(color.rawValue)"
    }
}

/// How a text layer sits on whatever is behind it (FR-019's "background
/// style"). Three states rather than a boolean, cycled by one button.
public enum TextBackgroundStyle: String, CaseIterable, Sendable {
    /// Bare text with a thin shadow so it stays legible on a busy photo.
    case none
    /// A pill filled with the chosen colour; the text flips to its contrast.
    case solid
    /// A dark pill; the text keeps the chosen colour.
    case translucent

    public var next: TextBackgroundStyle {
        switch self {
        case .none: .solid
        case .solid: .translucent
        case .translucent: .none
        }
    }

    public var name: String {
        String(localized: String.LocalizationValue("editor.text.background.\(rawValue)"), bundle: .module)
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
        switch self {
        case .bold: .black
        // Serif and monospace carry their own visual weight; at .bold they
        // read as heavier than the sans faces rather than equal to them.
        case .serif, .mono: .semibold
        case .classic, .rounded: .bold
        }
    }

    /// Shown on the chips, set in the typeface it names.
    ///
    /// The names describe the face, not the raw value — `classic` here is the
    /// default sans, while the prototype's `classic` was its serif. Renaming
    /// the raw values to match would have turned every stored `"classic"` into
    /// a serif overnight, so the labels moved instead.
    public var name: String {
        String(localized: String.LocalizationValue(Self.nameKey(for: self)), bundle: .module)
    }

    static func nameKey(for style: TextFontStyle) -> String {
        "editor.font.\(style.rawValue)"
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
