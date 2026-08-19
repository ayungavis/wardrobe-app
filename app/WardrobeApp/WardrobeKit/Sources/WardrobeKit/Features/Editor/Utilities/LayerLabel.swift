import Foundation

enum LayerLabel {
    static func title(for content: LayerContent, isChallengePhoto: Bool = false) -> String {
        if isChallengePhoto {
            return LocalizedKey.resolve("editor.layer.challengePhoto")
        }

        return switch content {
        case let .text(text): text.content
        case .photo: LocalizedKey.resolve("editor.layer.photo")
        case .sticker: LocalizedKey.resolve("editor.layer.sticker")
        case .drawing: LocalizedKey.resolve("editor.layer.drawing")
        }
    }

    static func kind(for content: LayerContent, isChallengePhoto: Bool = false) -> String {
        if isChallengePhoto {
            return LocalizedKey.resolve("editor.layer.challengePhoto")
        }

        return switch content {
        case .text: LocalizedKey.resolve("editor.layer.text")
        case .photo: LocalizedKey.resolve("editor.layer.photo")
        case .sticker: LocalizedKey.resolve("editor.layer.sticker")
        case let .drawing(drawing):
            String(localized: "editor.layer.strokes \(drawing.strokes.count)", bundle: .module)
        }
    }
}
