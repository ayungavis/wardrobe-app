import SwiftUI

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

    public var contrastText: Color {
        switch self {
        case .black, .red, .purple, .blue: .white
        case .white, .yellow, .orange, .pink, .cyan, .green: .black
        }
    }

    public var name: String {
        LocalizedKey.resolve(Self.nameKey(for: self))
    }

    static func nameKey(for color: TextColor) -> String {
        "editor.color.\(color.rawValue)"
    }
}

public enum TextBackgroundStyle: String, CaseIterable, Sendable {
    case none
    case solid
    case translucent

    public var next: TextBackgroundStyle {
        switch self {
        case .none: .solid
        case .solid: .translucent
        case .translucent: .none
        }
    }

    public var name: String {
        LocalizedKey.resolve("editor.text.background.\(rawValue)")
    }
}

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
        case .serif, .mono: .semibold
        case .classic, .rounded: .bold
        }
    }

    public var name: String {
        LocalizedKey.resolve(Self.nameKey(for: self))
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

    public var next: TextAlignmentStyle {
        switch self {
        case .leading: .center
        case .center: .trailing
        case .trailing: .leading
        }
    }
}
