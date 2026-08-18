import CoreGraphics
import Foundation
import Testing
@testable import WardrobeKit

/// The rules the canvas relies on, tested on the document itself so they hold
/// wherever an edit comes from — canvas today, layer panel later.
struct EditorDocumentEditingTests {
    private func makeDocument() -> EditorDocument {
        EditorDocument(layers: [
            EditorLayer(content: .photo(PhotoContent(photoID: "photo-1"))),
            EditorLayer(content: .sticker(StickerContent(emoji: "✨"))),
            EditorLayer(content: .text(TextContent(content: "OOTD"))),
        ])
    }

    // MARK: Transform (FR-085)

    @Test func aTransformReachesExactlyOneLayer() {
        var document = makeDocument()
        let target = document.layers[1]
        let untouched = document.layers.map(\.transform)

        document.updateTransform(ofLayer: target.id, to: ElementTransform(
            position: CGPoint(x: 0.2, y: 0.8), scale: 2, rotationDegrees: 30
        ))

        #expect(document.layers[1].transform.position == CGPoint(x: 0.2, y: 0.8))
        #expect(document.layers[0].transform == untouched[0])
        #expect(document.layers[2].transform == untouched[2])
    }

    @Test func anUnknownLayerIdChangesNothing() {
        var document = makeDocument()
        let before = document

        document.updateTransform(ofLayer: UUID(), to: ElementTransform(scale: 3))

        #expect(document == before)
    }

    /// The bound lives on the model, so it holds however the transform was
    /// produced — a gesture, a panel, or a document that arrived over the wire.
    @Test func anOutOfRangeScaleIsBroughtBackInside() {
        var document = makeDocument()
        let target = document.layers[2]

        document.updateTransform(ofLayer: target.id, to: ElementTransform(scale: 99))

        #expect(document.layers[2].transform.scale == ElementTransform.scaleRange.upperBound)
    }

    // MARK: Lock (FR-086)

    @Test func aLockedLayerKeepsItsGeometry() {
        var document = EditorDocument(layers: [
            EditorLayer(content: .sticker(StickerContent(emoji: "✨")), isLocked: true),
        ])
        let target = document.layers[0]

        document.updateTransform(ofLayer: target.id, to: ElementTransform(position: CGPoint(x: 0.1, y: 0.1)))

        #expect(document.layers[0].transform == .identity)
    }

    /// FR-087: deleting a locked layer takes an explicit unlock first, so the
    /// canvas gesture must not be able to do it.
    @Test func aLockedLayerCannotBeDeletedFromTheCanvas() {
        var document = EditorDocument(layers: [
            EditorLayer(content: .sticker(StickerContent(emoji: "✨")), isLocked: true),
        ])

        document.removeLayer(id: document.layers[0].id)

        #expect(document.layers.count == 1)
    }

    // MARK: Delete (FR-087)

    @Test func deletingRemovesOnlyThatLayer() {
        var document = makeDocument()
        let target = document.layers[1]

        document.removeLayer(id: target.id)

        #expect(document.layers.count == 2)
        #expect(!document.layers.contains { $0.id == target.id })
    }

    // MARK: Text upsert

    @Test func editingATextKeepsItsPlaceInTheStack() throws {
        var document = makeDocument()
        let target = document.layers[2]
        var item = try #require(target.textItem)
        item.content = "changed"

        document.upsertText(item)

        #expect(document.layers.count == 3)
        #expect(document.layers[2].id == target.id)
        guard case let .text(text) = document.layers[2].content else {
            Issue.record("expected a text layer")
            return
        }
        #expect(text.content == "changed")
    }

    @Test func aNewTextLandsOnTop() {
        var document = makeDocument()

        document.upsertText(TextItem(content: "new", position: CGPoint(x: 0.2, y: 0.3), scale: 1.5))

        #expect(document.layers.count == 4)
        #expect(document.layers[3].transform.position == CGPoint(x: 0.2, y: 0.3))
        #expect(document.layers[3].transform.scale == 1.5)
    }

    // MARK: Photo crop

    @Test func theCropIsReadAndWrittenOnThePhotoLayer() {
        var document = makeDocument()
        let crop = CropSpec(rect: CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.4))

        document.photoCrop = crop

        #expect(document.photoCrop == crop)
    }

    /// No photo means no place a crop could render, so storing one would only
    /// create a value nothing reads.
    @Test func settingACropWithNoPhotoLayerDoesNothing() {
        var document = EditorDocument(layers: [
            EditorLayer(content: .text(TextContent(content: "hi"))),
        ])

        document.photoCrop = CropSpec(rect: CGRect(x: 0, y: 0, width: 1, height: 1))

        #expect(document.photoCrop == nil)
        #expect(document.layers.count == 1)
    }

    // MARK: Round trip through the stored draft

    /// The editor works on a document but still stores an `EditDraft`, so this
    /// has to be a round trip rather than a copy — including the ids, which are
    /// what keeps a layer the same layer across a save.
    @Test func draftToDocumentAndBackIsIdentity() {
        let draft = EditDraft(
            crop: CropSpec(rect: CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.6)),
            texts: [
                TextItem(
                    content: "OOTD", position: CGPoint(x: 0.25, y: 0.75), scale: 1.8,
                    rotationDegrees: 12, colorName: TextColor.pink.rawValue, hasBackground: true,
                    fontName: TextFontStyle.serif.rawValue,
                    alignmentName: TextAlignmentStyle.leading.rawValue
                ),
                TextItem(content: "second"),
            ],
            stickers: [StickerItem(emoji: "✨", position: CGPoint(x: 0.9, y: 0.1), scale: 2)]
        )

        let restored = EditDraft(projecting: EditorDocument(migrating: draft, photoID: "photo-1"))

        #expect(restored == draft)
    }

    @Test func theRoundTripSurvivesAnEmptyDraft() {
        let restored = EditDraft(projecting: EditorDocument(migrating: EditDraft(), photoID: "photo-1"))

        #expect(restored == EditDraft())
    }

    /// Drawings have no home in the flat draft. Saying so here means the day it
    /// starts losing them is the day this test changes, not a silent morning.
    @Test func theProjectionDropsWhatTheFlatDraftCannotHold() {
        let document = EditorDocument(layers: [
            EditorLayer(content: .photo(PhotoContent(photoID: "photo-1"))),
            EditorLayer(content: .drawing(DrawingContent(strokes: [
                DrawingStroke(points: [DrawingPoint(unitX: 0.1, unitY: 0.2)]),
            ]))),
            EditorLayer(content: .text(TextContent(content: "kept"))),
        ])

        let draft = EditDraft(projecting: document)

        #expect(draft.texts.map(\.content) == ["kept"])
        #expect(draft.stickers.isEmpty)
    }
}
