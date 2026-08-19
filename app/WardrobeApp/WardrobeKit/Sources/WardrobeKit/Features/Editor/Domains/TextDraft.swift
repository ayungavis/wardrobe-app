import CoreGraphics
import Foundation

/// What the composer edits: one text layer, in pieces the composer can change.
///
/// Not a `TextItem` — that is the flat pre-canvas shape, kept only as a read
/// path for stored drafts. Editing through it meant the same styling fields
/// existed twice and could disagree; this carries the layer's real content and
/// its real transform, so there is one of each.
public struct TextDraft: Equatable, Sendable {
    /// The layer's id. Minted up front for a new text so the commit is an
    /// upsert either way.
    public let id: UUID
    public var content: TextContent
    /// The composer only ever changes `scale`. Position comes from wherever the
    /// user tapped and rotation from the canvas, and neither is the composer's
    /// to touch.
    public var transform: ElementTransform

    public init(id: UUID = UUID(), content: TextContent, transform: ElementTransform = .identity) {
        self.id = id
        self.content = content
        self.transform = transform
    }

    /// Whitespace-only text is nothing, and nothing is not worth storing.
    public var isBlank: Bool {
        content.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

public extension EditorLayer {
    /// The layer reopened for editing. Nil for every other kind of layer.
    var textDraft: TextDraft? {
        guard case let .text(content) = content else { return nil }
        return TextDraft(id: id, content: content, transform: transform)
    }
}
