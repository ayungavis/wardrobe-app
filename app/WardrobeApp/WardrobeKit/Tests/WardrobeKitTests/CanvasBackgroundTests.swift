import Foundation
import Testing
@testable import WardrobeKit

/// FR-091: the palette is fixed, stored in the document, and forgiving of a
/// token it has never seen.
struct CanvasBackgroundTests {
    @Test func aStoredBackgroundSurvivesARoundTrip() throws {
        let document = EditorDocument(layers: [], background: .sunset)

        let restored = try JSONDecoder().decode(
            EditorDocument.self, from: JSONEncoder().encode(document)
        )

        #expect(restored.background == .sunset)
    }

    /// The requirement is precise about this: fall back to the safe default
    /// **without discarding layers**. Refusing the document instead would cost
    /// the user their whole canvas over a colour.
    @Test func anUnknownPaletteTokenFallsBackAndKeepsTheLayers() throws {
        let json = """
        {
          "id": "\(UUID().uuidString)",
          "schemaVersion": 1,
          "background": "chartreuse",
          "layers": [
            { "id": "\(UUID().uuidString)", "content": { "kind": "text", "value": { "content": "hi" } } }
          ]
        }
        """

        let document = try JSONDecoder().decode(EditorDocument.self, from: Data(json.utf8))

        #expect(document.background == .default)
        #expect(document.textContents == ["hi"])
    }

    /// Deliberately the opposite rule to an unknown *layer*, which refuses.
    /// The stakes differ: a colour can be picked again, a layer cannot.
    @Test func anUnknownLayerKindStillRefuses() {
        let json = """
        {
          "id": "\(UUID().uuidString)",
          "schemaVersion": 1,
          "layers": [
            { "id": "\(UUID().uuidString)", "content": { "kind": "hologram", "value": {} } }
          ]
        }
        """

        #expect(throws: AppError.documentFromNewerApp) {
            try JSONDecoder().decode(EditorDocument.self, from: Data(json.utf8))
        }
    }

    @Test func aDocumentWithNoBackgroundUsesTheDefault() throws {
        let json = """
        { "id": "\(UUID().uuidString)", "schemaVersion": 1, "layers": [] }
        """

        #expect(try JSONDecoder().decode(EditorDocument.self, from: Data(json.utf8)).background == .default)
    }

    @Test func everyPaletteEntryHasColours() {
        for background in CanvasBackground.allCases {
            #expect(background.colors.count >= 2, "\(background.rawValue) needs at least two stops")
        }
    }

    /// A ninth background added without its string would put the raw key on
    /// screen under its swatch. Checked against the catalogue file rather than
    /// through `String(localized:)`, because SwiftPM copies `.xcstrings`
    /// uncompiled — under `swift test` *nothing* localizes, so a runtime check
    /// would fail for every key and prove nothing.
    ///
    /// Reading the catalogue also catches the half-missing case a runtime check
    /// never could: an entry that has English but no Indonesian.
    @Test func everyPaletteEntryHasATranslatedName() throws {
        let url = try #require(Bundle.module.url(forResource: "Localizable", withExtension: "xcstrings"))
        let catalogue = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        let strings = try #require((catalogue as? [String: Any])?["strings"] as? [String: Any])

        for background in CanvasBackground.allCases {
            let key = CanvasBackground.nameKey(for: background)
            let entry = try #require(strings[key] as? [String: Any], "\(key) is not in the catalogue")
            let localizations = try #require(entry["localizations"] as? [String: Any])

            for language in ["en", "id"] {
                let unit = (localizations[language] as? [String: Any])?["stringUnit"] as? [String: Any]
                let value = unit?["value"] as? String
                #expect(value?.isEmpty == false, "\(key) has no \(language) value")
            }

            // Built at runtime from the raw value, so the extractor prunes these
            // as stale and the compiled catalogue loses them. This flag is the
            // only thing keeping the names on screen.
            #expect(
                entry["extractionState"] as? String == "manual",
                "\(key) must be pinned manual — its key is assembled at runtime"
            )
        }
    }
}
