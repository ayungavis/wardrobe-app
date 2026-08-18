import Testing
@testable import WardrobeKit

/// The panel row and VoiceOver read from here, so what it returns is the one
/// name a layer has.
///
/// SwiftPM copies `.xcstrings` uncompiled, so under `swift test` a localized
/// lookup returns its key. That is exactly what makes the text branch worth
/// pinning: it is the only one that must *not* be a key.
struct LayerLabelTests {
    @Test func aTextLayerIsNamedByWhatItSays() {
        let title = LayerLabel.title(for: .text(TextContent(content: "OOTD")))

        #expect(title == "OOTD")
    }

    /// Every other kind is named by its kind, so the title is a catalogue key
    /// rather than anything user-generated.
    @Test func everyOtherKindIsNamedByItsKind() {
        #expect(LayerLabel.title(for: .photo(PhotoContent(photoID: "p"))) == "editor.layer.photo")
        #expect(LayerLabel.title(for: .sticker(StickerContent(emoji: "✨"))) == "editor.layer.sticker")
        #expect(LayerLabel.title(for: .drawing(DrawingContent(strokes: []))) == "editor.layer.drawing")
    }

    /// A text layer's second line says what it is, not what it says — the row
    /// would otherwise print the same string twice.
    @Test func theSecondLineIsAlwaysTheKind() {
        let kind = LayerLabel.kind(for: .text(TextContent(content: "OOTD")))

        #expect(kind == "editor.layer.text")
    }

    /// The stroke count is the one thing a 46-point thumbnail cannot show, so
    /// it has to survive into the subtitle.
    @Test func aDrawingCountsItsStrokes() {
        let content = DrawingContent(strokes: [
            DrawingStroke(points: [DrawingPoint(unitX: 0.1, unitY: 0.1)]),
            DrawingStroke(points: [DrawingPoint(unitX: 0.2, unitY: 0.2)]),
        ])

        #expect(LayerLabel.kind(for: .drawing(content)).contains("2"))
    }
}
