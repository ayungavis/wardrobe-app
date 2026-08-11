import CoreGraphics
import Foundation

/// Non-destructive edit instructions (PRD FR-018, §18.5). The original photo
/// is never modified — rendering applies these on top at export time.
public struct EditDraft: Codable, Equatable, Sendable {
    public var crop: CropSpec?
    public var texts: [TextItem]

    public init(crop: CropSpec? = nil, texts: [TextItem] = []) {
        self.crop = crop
        self.texts = texts
    }

    public var isEmpty: Bool {
        crop == nil && texts.isEmpty
    }
}

/// Visible rect in unit image space (all components 0...1).
public struct CropSpec: Codable, Equatable, Sendable {
    public var rect: CGRect

    public init(rect: CGRect) {
        self.rect = rect
    }
}

public struct TextItem: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public var content: String
    /// Center position in unit image space (0...1).
    public var position: CGPoint
    public var scale: CGFloat

    public init(
        id: UUID = UUID(),
        content: String,
        position: CGPoint = CGPoint(x: 0.5, y: 0.5),
        scale: CGFloat = 1
    ) {
        self.id = id
        self.content = content
        self.position = position
        self.scale = scale
    }
    // ponytail: no rotation/color/font — one styled text token; add fields when the design asks.
}
