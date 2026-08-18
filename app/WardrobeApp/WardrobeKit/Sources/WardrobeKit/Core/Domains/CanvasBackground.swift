import Foundation
import SwiftUI

/// The fixed canvas background palette (FR-091). A content palette, the way
/// `TextColor` is — a choice about the picture, not a design-system token.
/// Users pick from it and cannot add to it, which is what keeps the editor
/// bounded and every stored document renderable by every build.
public enum CanvasBackground: String, CaseIterable, Identifiable, Sendable {
    case white, cream, blush, lavender, sky, mint, sunset, midnight

    public static let `default` = CanvasBackground.white

    public var id: String {
        rawValue
    }

    /// Two stops, top-leading to bottom-trailing — except `sunset`, which needs
    /// three to get through orange without going muddy.
    public var colors: [Color] {
        switch self {
        case .white: [.white, .white]
        case .cream: [Color(red: 1, green: 0.97, blue: 0.88), Color(red: 0.98, green: 0.90, blue: 0.76)]
        case .blush: [Color(red: 1, green: 0.89, blue: 0.92), Color(red: 0.97, green: 0.66, blue: 0.77)]
        case .lavender: [Color(red: 0.91, green: 0.86, blue: 1), Color(red: 0.68, green: 0.55, blue: 0.94)]
        case .sky: [Color(red: 0.78, green: 0.93, blue: 1), Color(red: 0.34, green: 0.68, blue: 0.96)]
        case .mint: [Color(red: 0.82, green: 0.98, blue: 0.88), Color(red: 0.34, green: 0.78, blue: 0.61)]
        case .sunset: [
                Color(red: 1, green: 0.72, blue: 0.38),
                Color(red: 0.96, green: 0.34, blue: 0.55),
                Color(red: 0.43, green: 0.25, blue: 0.76),
            ]
        case .midnight: [Color(red: 0.08, green: 0.10, blue: 0.22), Color(red: 0.25, green: 0.13, blue: 0.42)]
        }
    }

    /// Resolved here rather than handed to a view as a key, the same way
    /// `AppError.userMessage` does it — inside the package, where `.module` is
    /// the bundle that actually holds the catalogue, and where a test can catch
    /// a palette entry whose string was never written.
    public var name: String {
        LocalizedKey.resolve(Self.nameKey(for: self))
    }

    /// Built from the raw value, so the string extractor never sees these keys
    /// in source and marks them stale — which drops them from the compiled
    /// catalogue and puts the key itself on screen. They are pinned
    /// `"extractionState": "manual"` in `Localizable.xcstrings` for exactly
    /// that reason; do not "clean" it off.
    static func nameKey(for background: CanvasBackground) -> String {
        "editor.background.\(background.rawValue)"
    }
}

extension CanvasBackground: Codable {
    /// FR-091 to the letter: a palette token this build has never heard of
    /// falls back to the safe default **without discarding layers**.
    ///
    /// Deliberately the opposite of `LayerContent`, where an unknown kind
    /// refuses to decode at all. The stakes decide the rule: an unknown
    /// background costs a colour the user can pick again, an unknown layer
    /// would quietly delete work.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CanvasBackground(rawValue: raw) ?? .default
    }
}
