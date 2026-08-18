import Foundation

/// What a layer is called.
///
/// One place, because two of them read it: the panel row prints it and
/// VoiceOver speaks it on the canvas. Split in two, the same layer could end up
/// with two different names depending on where you met it.
enum LayerLabel {
    /// The row's first line, and the canvas layer's accessibility label. A text
    /// layer is called by what it says — nothing else identifies it.
    static func title(for content: LayerContent) -> String {
        switch content {
        case let .text(text): text.content
        case .photo: LocalizedKey.resolve("editor.layer.photo")
        case .sticker: LocalizedKey.resolve("editor.layer.sticker")
        case .drawing: LocalizedKey.resolve("editor.layer.drawing")
        }
    }

    /// The row's second line: which kind of layer, and for a drawing how much
    /// is in it — the one thing a 46-point thumbnail cannot show.
    static func kind(for content: LayerContent) -> String {
        switch content {
        case .text: LocalizedKey.resolve("editor.layer.text")
        case .photo: LocalizedKey.resolve("editor.layer.photo")
        case .sticker: LocalizedKey.resolve("editor.layer.sticker")
        case let .drawing(drawing):
            String(localized: "editor.layer.strokes \(drawing.strokes.count)", bundle: .module)
        }
    }
}
