import CoreGraphics
import Foundation
import Testing
@testable import WardrobeKit

/// The document is stored on people's phones and, after ✓, on the server. Its
/// shape is the hardest thing here to change later, so the rules that protect
/// it are tested directly.
struct EditorDocumentTests {
    private func encode(_ document: EditorDocument) throws -> Data {
        try JSONEncoder().encode(document)
    }

    private func decode(_ data: Data) throws -> EditorDocument {
        try JSONDecoder().decode(EditorDocument.self, from: data)
    }

    private func makeDocument(layers: [EditorLayer]) -> EditorDocument {
        EditorDocument(layers: layers, background: .mint)
    }

    // MARK: Round trip

    @Test func everyLayerKindSurvivesARoundTrip() throws {
        let document = makeDocument(layers: [
            EditorLayer(content: .photo(PhotoContent(photoID: "photo-1"))),
            EditorLayer(content: .text(TextContent(content: "OOTD"))),
            EditorLayer(content: .sticker(StickerContent(emoji: "✨"))),
            EditorLayer(content: .drawing(DrawingContent(strokes: [
                DrawingStroke(points: [DrawingPoint(unitX: 0.1, unitY: 0.2)], color: .blue, width: .thick),
            ]))),
        ])

        let restored = try decode(encode(document))

        #expect(restored == document)
    }

    /// Ids are how a layer stays the same layer across a save, an undo, and a
    /// sync — losing them would silently duplicate work.
    @Test func layerIdentityIsPreserved() throws {
        let layer = EditorLayer(content: .sticker(StickerContent(emoji: "🌸")))
        let document = makeDocument(layers: [layer])

        let restored = try decode(encode(document))

        #expect(restored.layers.map(\.id) == [layer.id])
        #expect(restored.id == document.id)
    }

    @Test func arrayOrderIsTheZOrder() throws {
        let bottom = EditorLayer(content: .photo(PhotoContent(photoID: "p")))
        let top = EditorLayer(content: .text(TextContent(content: "on top")))

        let restored = try decode(encode(makeDocument(layers: [bottom, top])))

        #expect(restored.layers.map(\.id) == [bottom.id, top.id])
    }

    // MARK: Lenient within a version

    @Test func fieldsAddedLaterFallBackToDefaults() throws {
        let json = """
        {
          "id": "\(UUID().uuidString)",
          "schemaVersion": 1,
          "layers": [
            { "id": "\(UUID().uuidString)", "content": { "kind": "text", "value": { "content": "hi" } } }
          ]
        }
        """

        let document = try decode(Data(json.utf8))

        #expect(document.background == .white)
        #expect(document.layers.first?.transform == .identity)
        #expect(document.layers.first?.isLocked == false)
        guard case let .text(text) = document.layers.first?.content else {
            Issue.record("expected a text layer")
            return
        }
        #expect(text.fontStyle == .classic)
        #expect(text.textColor == .white)
    }

    @Test func aDocumentWithNoLayersDecodesRatherThanFailing() throws {
        let json = """
        { "id": "\(UUID().uuidString)", "schemaVersion": 1 }
        """

        let document = try decode(Data(json.utf8))

        #expect(document.layers.isEmpty)
    }

    // MARK: Unforgiving across a version (FR-098)

    /// The rule that matters most here: a document from a newer build must not
    /// half-decode, because the layers this build cannot name would vanish and
    /// the next save would write them out of existence.
    @Test func aDocumentFromANewerAppRefusesToDecode() {
        let json = """
        {
          "id": "\(UUID().uuidString)",
          "schemaVersion": \(EditorDocument.currentSchemaVersion + 1),
          "layers": []
        }
        """

        #expect(throws: AppError.documentFromNewerApp) {
            try decode(Data(json.utf8))
        }
    }

    @Test func theCurrentVersionDecodes() throws {
        let document = try decode(encode(makeDocument(layers: [])))

        #expect(document.schemaVersion == EditorDocument.currentSchemaVersion)
    }

    /// A document with no version at all predates versioning, so it is read as
    /// version 1 rather than rejected.
    @Test func aDocumentWithoutAVersionIsTreatedAsTheFirst() throws {
        let json = """
        { "id": "\(UUID().uuidString)", "layers": [] }
        """

        #expect(try decode(Data(json.utf8)).schemaVersion == 1)
    }

    // MARK: Migration from the flat draft

    @Test func migrationPutsThePhotoAtTheBottomWithItsCrop() {
        let crop = CropSpec(rect: CGRect(x: 0.1, y: 0.2, width: 0.6, height: 0.45))
        let draft = EditDraft(crop: crop, texts: [TextItem(content: "hi")], stickers: [])

        let document = EditorDocument(migrating: draft, photoID: "photo-1")

        guard case let .photo(photo) = document.layers.first?.content else {
            Issue.record("the photo must be the bottom layer")
            return
        }
        #expect(photo.photoID == "photo-1")
        #expect(photo.crop == crop)
    }

    /// The order is read off the renderers, not chosen: `EditorCanvasView` and
    /// `DocumentCanvasView` both draw stickers first and texts over them.
    @Test func migrationKeepsStickersBelowTextsInOrder() {
        let draft = EditDraft(
            texts: [TextItem(content: "first"), TextItem(content: "second")],
            stickers: [StickerItem(emoji: "✨")]
        )

        let document = EditorDocument(migrating: draft, photoID: "p")

        let kinds = document.layers.map { layer -> String in
            switch layer.content {
            case .photo: "photo"
            case .text: "text"
            case .sticker: "sticker"
            case .drawing: "drawing"
            }
        }
        #expect(kinds == ["photo", "sticker", "text", "text"])
    }

    /// Transform and styling are the work the user actually did; losing them in
    /// migration would be indistinguishable from losing the edit.
    @Test func migrationPreservesPlacementAndStyling() {
        let text = TextItem(
            content: "OOTD",
            position: CGPoint(x: 0.25, y: 0.75),
            scale: 1.8,
            rotationDegrees: 12,
            colorName: TextColor.pink.rawValue,
            hasBackground: true,
            fontName: TextFontStyle.serif.rawValue,
            alignmentName: TextAlignmentStyle.leading.rawValue
        )

        let document = EditorDocument(migrating: EditDraft(texts: [text]), photoID: "p")

        let layer = document.layers[1]
        #expect(layer.transform.position == text.position)
        #expect(layer.transform.scale == text.scale)
        #expect(layer.transform.rotationDegrees == text.rotationDegrees)
        guard case let .text(content) = layer.content else {
            Issue.record("expected a text layer")
            return
        }
        #expect(content.textColor == .pink)
        #expect(content.fontStyle == .serif)
        #expect(content.alignmentStyle == .leading)
        #expect(content.backgroundStyle == .solid)
    }

    @Test func anEmptyDraftBecomesJustThePhoto() {
        let document = EditorDocument(migrating: EditDraft(), photoID: "p")

        #expect(document.layers.count == 1)
        #expect(document.layers.first?.transform == .identity)
    }

    // MARK: Stroke sanitising

    @Test func nonFinitePointsAreDropped() {
        let stroke = DrawingStroke(points: [
            DrawingPoint(unitX: 0.1, unitY: 0.1),
            DrawingPoint(unitX: .nan, unitY: 0.5),
            DrawingPoint(unitX: 0.2, unitY: .infinity),
            DrawingPoint(unitX: 0.3, unitY: 0.3),
        ])

        #expect(stroke.sanitized()?.points.count == 2)
    }

    @Test func strayPointsArePulledBackOntoTheCanvas() {
        let stroke = DrawingStroke(points: [DrawingPoint(unitX: -4, unitY: 9)])

        let cleaned = stroke.sanitized()

        #expect(cleaned?.points == [DrawingPoint(unitX: 0, unitY: 1)])
    }

    @Test func aStrokeIsCappedRatherThanStoredForever() {
        let stroke = DrawingStroke(points: (0 ..< 5000).map { DrawingPoint(unitX: Double($0) / 5000, unitY: 0.5) })

        #expect(stroke.sanitized()?.points.count == DrawingStroke.maximumPointCount)
    }

    /// A stroke with nothing drawable left is nothing, not an invisible entry
    /// that still costs bytes on every sync.
    @Test func aStrokeWithNoUsablePointsIsNil() {
        let stroke = DrawingStroke(points: [DrawingPoint(unitX: .nan, unitY: .nan)])

        #expect(stroke.sanitized() == nil)
    }

    @Test func sanitisingKeepsTheStrokesIdentityAndStyle() {
        let stroke = DrawingStroke(
            points: [DrawingPoint(unitX: 0.5, unitY: 0.5)], color: .orange, width: .thin
        )

        let cleaned = stroke.sanitized()

        #expect(cleaned?.id == stroke.id)
        #expect(cleaned?.color == .orange)
        #expect(cleaned?.width == .thin)
    }

    // MARK: The stored shape itself

    /// The wire shape is part of the contract, not an implementation detail:
    /// documents written today are read by builds that do not exist yet. A
    /// discriminator keyed by name survives compiler changes; a synthesized
    /// `_0` label does not.
    @Test func layerContentIsStoredUnderANamedDiscriminator() throws {
        let data = try encode(makeDocument(layers: [
            EditorLayer(content: .sticker(StickerContent(emoji: "✨"))),
        ]))

        let json = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let layers = try #require(json["layers"] as? [[String: Any]])
        let content = try #require(layers.first?["content"] as? [String: Any])

        #expect(content["kind"] as? String == "sticker")
        // The layer tag is frozen; what the sticker itself stores is pinned in
        // StickerCatalogueTests, which owns that shape.
        let art = try #require((content["value"] as? [String: Any])?["art"] as? [String: Any])
        #expect(art["kind"] as? String == "catalogue")
        #expect(art["value"] as? String == "emoji.sparkles")
    }

    /// A layer kind this build has never heard of is the same situation as a
    /// newer schema version, and gets the same actionable answer.
    @Test func anUnknownLayerKindIsReportedAsANewerApp() {
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
            try decode(Data(json.utf8))
        }
    }
}
