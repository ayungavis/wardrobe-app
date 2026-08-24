import CoreGraphics
import Foundation
import Testing
@testable import WardrobeKit

/// FR-091: the palette is fixed, stored in the document, and forgiving of a
/// token it has never seen.
struct CanvasBackgroundTests {
    @Test func aStoredBackgroundSurvivesARoundTrip() throws {
        let document = EditorDocument(layers: [], background: .palette(.sunset))

        let restored = try JSONDecoder().decode(
            EditorDocument.self, from: JSONEncoder().encode(document)
        )

        #expect(restored.background == .palette(.sunset))
    }

    /// The requirement is precise about this: fall back to the safe default
    /// **without discarding layers**. Refusing the document instead would cost
    /// the user their whole canvas over a colour.
    @Test func anUnknownPaletteTokenFallsBackAndKeepsTheLayers() throws {
        let json = """
        {
          "id": "\(UUID.v7())",
          "schemaVersion": 1,
          "background": "chartreuse",
          "layers": [
            { "id": "\(UUID.v7())", "content": { "kind": "text", "value": { "content": "hi" } } }
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
          "id": "\(UUID.v7())",
          "schemaVersion": 1,
          "layers": [
            { "id": "\(UUID.v7())", "content": { "kind": "hologram", "value": {} } }
          ]
        }
        """

        #expect(throws: AppError.documentFromNewerApp) {
            try JSONDecoder().decode(EditorDocument.self, from: Data(json.utf8))
        }
    }

    /// The shape that existed before photo backgrounds: a bare string. It has to
    /// keep reading, because every document already on a device is written that
    /// way — and it has to keep *writing* that way too, so builds that predate
    /// this change are not locked out of documents they could render.
    @Test func aPaletteStillEncodesAsABareString() throws {
        let encoded = try JSONEncoder().encode(
            EditorDocument(layers: [], background: .palette(.mint))
        )
        let json = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        #expect(json["background"] as? String == "mint")
    }

    @Test func aPhotoBackgroundSurvivesARoundTripWithItsCrop() throws {
        let crop = CropSpec(rect: CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.6))
        let document = EditorDocument(layers: [], background: .photo(id: id("bg-1"), crop: crop))

        let restored = try JSONDecoder().decode(
            EditorDocument.self, from: JSONEncoder().encode(document)
        )

        #expect(restored.background == .photo(id: id("bg-1"), crop: crop))
    }

    @Test func aPhotoBackgroundWithoutACropSurvivesToo() throws {
        let document = EditorDocument(layers: [], background: .photo(id: id("bg-1"), crop: nil))

        let restored = try JSONDecoder().decode(
            EditorDocument.self, from: JSONEncoder().encode(document)
        )

        #expect(restored.background == .photo(id: id("bg-1"), crop: nil))
    }

    /// The background's file has the same lifetime as any layer's, and every
    /// loader and cleanup path reads `photoIDs` to find it.
    @Test func photoIDsIncludesTheBackground() {
        let document = EditorDocument(
            layers: [EditorLayer(content: .photo(PhotoContent(photoID: id("layer-1"))))],
            background: .photo(id: id("bg-1"), crop: nil)
        )

        #expect(document.photoIDs.sorted() == [id("bg-1"), id("layer-1")])
        // Layer lookups must not start finding the background.
        #expect(document.photoLayerID(showing: id("bg-1")) == nil)
    }

    /// Undo refreshes previews by comparing this, so a background crop missing
    /// from it means undoing one leaves the canvas drawing the old pixels.
    @Test func photoCropsIncludesTheBackground() {
        let crop = CropSpec(rect: CGRect(x: 0, y: 0, width: 0.5, height: 0.5))
        let document = EditorDocument(
            layers: [EditorLayer(content: .photo(PhotoContent(photoID: id("layer-1"))))],
            background: .photo(id: id("bg-1"), crop: crop)
        )

        #expect(document.photoCrops[id("bg-1")] == crop)
        #expect(document.photoCrops[id("layer-1")] == CropSpec?.none)
    }

    @Test func aDocumentWithNoBackgroundUsesTheDefault() throws {
        let json = """
        { "id": "\(UUID.v7())", "schemaVersion": 1, "layers": [] }
        """

        #expect(try JSONDecoder().decode(EditorDocument.self, from: Data(json.utf8)).background == .default)
    }

    @Test func everyPaletteEntryHasColours() {
        for palette in CanvasBackground.Palette.allCases {
            #expect(palette.colors.count >= 2, "\(palette.rawValue) needs at least two stops")
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

        for palette in CanvasBackground.Palette.allCases {
            let key = palette.nameKey
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
