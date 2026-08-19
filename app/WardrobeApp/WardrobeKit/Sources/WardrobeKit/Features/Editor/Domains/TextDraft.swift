import CoreGraphics
import Foundation

public struct TextDraft: Equatable, Sendable {
    public let id: UUID
    public var content: TextContent
    public var transform: ElementTransform

    public init(id: UUID = UUID(), content: TextContent, transform: ElementTransform = .identity) {
        self.id = id
        self.content = content
        self.transform = transform
    }

    public var isBlank: Bool {
        content.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

public extension EditorLayer {
    var textDraft: TextDraft? {
        guard case let .text(content) = content else { return nil }
        return TextDraft(id: id, content: content, transform: transform)
    }
}
