import Foundation
import Testing
@testable import WardrobeKit

/// FR-019's text styling: font, colour, alignment, background style, and size.
struct TextStyleTests {
    // MARK: Background style (the boolean that grew a third state)

    /// Every text stored before this stage said `hasBackground` and nothing
    /// else. The pill it meant is the solid one.
    @Test func aStoredBooleanBackgroundIsReadAsTheSolidPill() throws {
        let json = """
        { "content": "hi", "colorName": "pink", "hasBackground": true }
        """

        let content = try JSONDecoder().decode(TextContent.self, from: Data(json.utf8))

        #expect(content.backgroundStyle == .solid)
        #expect(content.textColor == .pink)
    }

    @Test func aStoredFalseBackgroundIsReadAsNone() throws {
        let json = """
        { "content": "hi", "hasBackground": false }
        """

        #expect(try JSONDecoder().decode(TextContent.self, from: Data(json.utf8)).backgroundStyle == .none)
    }

    /// The same call `CanvasBackground` makes: an unknown style costs a look,
    /// not the words, so it falls back instead of refusing.
    @Test func anUnknownBackgroundStyleFallsBackWithoutLosingTheText() throws {
        let json = """
        { "content": "still here", "backgroundStyleName": "neon" }
        """

        let content = try JSONDecoder().decode(TextContent.self, from: Data(json.utf8))

        #expect(content.backgroundStyle == .none)
        #expect(content.content == "still here")
    }

    @Test func theBackgroundStyleSurvivesARoundTrip() throws {
        let content = TextContent(content: "hi", backgroundStyle: .translucent)

        let restored = try JSONDecoder().decode(
            TextContent.self, from: JSONEncoder().encode(content)
        )

        #expect(restored == content)
    }

    /// The old key is a read path, not a format we keep producing.
    @Test func theBooleanIsNeverWrittenAgain() throws {
        let data = try JSONEncoder().encode(TextContent(content: "hi", backgroundStyle: .solid))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(json["backgroundStyleName"] as? String == "solid")
        #expect(json["hasBackground"] == nil)
    }

    // MARK: Cycling

    @Test func backgroundStyleCyclesBackToWhereItStarted() {
        #expect(TextBackgroundStyle.none.next == .solid)
        #expect(TextBackgroundStyle.solid.next == .translucent)
        #expect(TextBackgroundStyle.translucent.next == .none)
    }

    @Test func alignmentCyclesBackToWhereItStarted() {
        #expect(TextAlignmentStyle.leading.next.next.next == .leading)
    }

    // MARK: Palette

    /// A colour is only usable as a pill if something readable can sit on it.
    @Test func everyColourNamesAContrastingText() {
        let light: Set<TextColor> = [.white, .yellow, .orange, .pink, .cyan, .green]

        for color in TextColor.allCases {
            #expect(color.contrastText == (light.contains(color) ? .black : .white))
        }
    }

    /// Raw values are stored. Renaming one silently restyles every text that
    /// already uses it — which is exactly why the display names carry the
    /// prototype's wording and these do not.
    @Test func theStoredPaletteNamesAreUnchanged() {
        #expect(TextColor.allCases.map(\.rawValue) == [
            "white", "black", "yellow", "orange", "red", "pink", "purple", "blue", "cyan", "green",
        ])
        #expect(TextFontStyle.allCases.map(\.rawValue) == [
            "classic", "bold", "rounded", "serif", "mono",
        ])
    }

    // MARK: Names in the catalogue

    /// Font and colour names are assembled from raw values at runtime, so the
    /// extractor prunes them as stale unless they are pinned. Checked against
    /// the catalogue file because SwiftPM copies `.xcstrings` uncompiled —
    /// under `swift test` nothing localizes.
    @Test func everyFontAndColourHasATranslatedPinnedName() throws {
        let url = try #require(Bundle.module.url(forResource: "Localizable", withExtension: "xcstrings"))
        let catalogue = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        let strings = try #require((catalogue as? [String: Any])?["strings"] as? [String: Any])

        let keys = TextFontStyle.allCases.map { TextFontStyle.nameKey(for: $0) }
            + TextColor.allCases.map { TextColor.nameKey(for: $0) }
            + TextBackgroundStyle.allCases.map { "editor.text.background.\($0.rawValue)" }

        for key in keys {
            let entry = try #require(strings[key] as? [String: Any], "\(key) is not in the catalogue")
            let localizations = try #require(entry["localizations"] as? [String: Any])

            for language in ["en", "id"] {
                let unit = (localizations[language] as? [String: Any])?["stringUnit"] as? [String: Any]
                #expect((unit?["value"] as? String)?.isEmpty == false, "\(key) has no \(language) value")
            }

            #expect(
                entry["extractionState"] as? String == "manual",
                "\(key) must be pinned manual — its key is assembled at runtime"
            )
        }
    }
}
