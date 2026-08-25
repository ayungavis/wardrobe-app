import Foundation
import Testing
@testable import WardrobeKit

/// FR-019's catalogue, and the storage contract underneath it.
struct StickerCatalogueTests {
    /// A wardrobe item's illustration is a sticker whose id names the item, so
    /// re-stylising the item updates every canvas it was already placed on.
    @Test func anItemStickerCarriesTheItemItNames() {
        let itemID = UUID()

        let art = StickerArt.item(itemID)

        #expect(art.wardrobeItemID == itemID)
        #expect(StickerArt.catalogue("emoji.fire").wardrobeItemID == nil)
    }

    /// It rides the catalogue kind on purpose: a new kind would make every
    /// older build refuse the whole document instead of one sticker.
    @Test func anItemStickerStaysReadableByBuildsThatNeverHeardOfIt() throws {
        let itemID = UUID()
        let encoded = try JSONEncoder().encode(StickerArt.item(itemID))
        let json = try #require(
            try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )

        #expect(json["kind"] as? String == "catalogue")
        #expect(try JSONDecoder().decode(StickerArt.self, from: encoded) == .item(itemID))
    }

    // MARK: Reading what was stored before the catalogue

    /// A document written when a sticker was just a glyph must keep it.
    @Test func aStoredGlyphInTheCatalogueBecomesThatEntry() throws {
        let json = Data(#"{"emoji":"🔥"}"#.utf8)

        let content = try JSONDecoder().decode(StickerContent.self, from: json)

        #expect(content.art == .catalogue("emoji.fire"))
    }

    /// The case that matters most: an emoji the catalogue never claimed. It
    /// still decodes, and it still draws — losing it would delete work.
    @Test func aStoredGlyphOutsideTheCatalogueKeepsItsGlyph() throws {
        let json = Data(#"{"emoji":"🦕"}"#.utf8)

        let content = try JSONDecoder().decode(StickerContent.self, from: json)

        #expect(content.art == .emoji("🦕"))
        #expect(content.art.design == .emoji("🦕"))
    }

    @Test func bothFormsSurviveARoundTrip() throws {
        for art in [StickerArt.catalogue("sticker.heart"), .emoji("🦕")] {
            let restored = try JSONDecoder().decode(
                StickerContent.self, from: JSONEncoder().encode(StickerContent(art: art))
            )
            #expect(restored.art == art)
        }
    }

    /// The glyph key is a read path, not a format we keep producing.
    @Test func theGlyphKeyIsNeverWrittenAgain() throws {
        let data = try JSONEncoder().encode(StickerContent(emoji: "🔥"))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(json["emoji"] == nil)
        let art = try #require(json["art"] as? [String: Any])
        #expect(art["kind"] as? String == "catalogue")
        #expect(art["value"] as? String == "emoji.fire")
    }

    /// FR-019: an unavailable catalogue asset does not block editing. An id we
    /// no longer ship decodes, keeps its layer, and draws a placeholder.
    @Test func anUnknownCatalogueIdSurvivesAndDrawsSomething() throws {
        let json = Data(#"{"art":{"kind":"catalogue","value":"sticker.retired"}}"#.utf8)

        let content = try JSONDecoder().decode(StickerContent.self, from: json)

        #expect(content.art == .catalogue("sticker.retired"))
        #expect(content.art.design == nil)
    }

    /// An unknown *kind* is different: that is a schema this build cannot read,
    /// and FR-098 says refuse rather than half-decode.
    @Test func anUnknownArtKindRefuses() {
        let json = Data(#"{"art":{"kind":"hologram","value":"x"}}"#.utf8)

        #expect(throws: AppError.documentFromNewerApp) {
            try JSONDecoder().decode(StickerContent.self, from: json)
        }
    }

    // MARK: The catalogue itself

    /// Ids are stored inside people's documents. Renaming or removing one
    /// deletes that sticker from work they have already made, so the list is
    /// pinned and a change has to be deliberate.
    @Test func catalogueIdsAreStable() {
        #expect(StickerCatalogue.emojis.count == 47)
        #expect(StickerCatalogue.offlineStickers.map(\.id) == [
            "sticker.heart", "sticker.star", "sticker.sparkles", "sticker.sun",
            "sticker.cloud", "sticker.moon", "sticker.camera", "sticker.music",
            "sticker.location", "sticker.verified", "sticker.flame", "sticker.leaf",
        ])
        // The wardrobe-specific emoji this app kept when it took the prototype's set.
        for id in ["emoji.dress", "emoji.jeans", "emoji.sneaker", "emoji.handbag"] {
            #expect(StickerCatalogue.entry(id: id) != nil, "\(id) went missing")
        }
    }

    @Test func everyIdIsUnique() {
        let ids = StickerCatalogue.all.map(\.id)

        #expect(Set(ids).count == ids.count)
    }

    @Test func everyGlyphIsUniqueSoLegacyLookupIsUnambiguous() {
        let glyphs = StickerCatalogue.all.compactMap { entry -> String? in
            guard case let .emoji(glyph) = entry.design else { return nil }
            return glyph
        }

        #expect(Set(glyphs).count == glyphs.count)
    }

    // MARK: Categories

    @Test func recentIsBuiltFromTheIdsGivenInOrder() {
        let entries = StickerCatalogue.entries(
            in: .recent, recentIDs: ["sticker.heart", "emoji.fire"]
        )

        #expect(entries.map(\.id) == ["sticker.heart", "emoji.fire"])
    }

    @Test func recentSkipsIdsTheCatalogueNoLongerShips() {
        let entries = StickerCatalogue.entries(
            in: .recent, recentIDs: ["sticker.retired", "emoji.fire"]
        )

        #expect(entries.map(\.id) == ["emoji.fire"])
    }

    // MARK: Names in the catalogue

    /// Assembled from ids at runtime, so the extractor prunes them as stale
    /// unless pinned. Read from the file because SwiftPM copies `.xcstrings`
    /// uncompiled — nothing localizes under `swift test`.
    @Test func everyStickerAndCategoryHasATranslatedPinnedName() throws {
        let url = try #require(Bundle.module.url(forResource: "Localizable", withExtension: "xcstrings"))
        let catalogue = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        let strings = try #require((catalogue as? [String: Any])?["strings"] as? [String: Any])

        let keys = StickerCatalogue.all.map { StickerCatalogueEntry.nameKey(for: $0.id) }
            + StickerCategory.allCases.map { "editor.sticker.category.\($0.rawValue)" }

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
