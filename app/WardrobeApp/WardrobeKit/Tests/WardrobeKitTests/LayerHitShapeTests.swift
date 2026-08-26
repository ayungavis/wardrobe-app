import CoreGraphics
import SwiftUI
import Testing
@testable import WardrobeKit

/// Where a finger has to land to hit a layer.
///
/// Testable directly because a `Shape` is just a `Path`, and `Path.contains` is
/// the same question hit-testing asks.
@MainActor
struct LayerHitShapeTests {
    private let box = CGRect(x: 0, y: 0, width: 200, height: 200)

    private func diagonalDrawing(width: DrawingWidth = .medium) -> LayerContent {
        .drawing(DrawingContent(strokes: [
            DrawingStroke(
                points: [
                    DrawingPoint(unitX: 0.1, unitY: 0.1),
                    DrawingPoint(unitX: 0.9, unitY: 0.9),
                ],
                color: .black,
                width: width
            ),
        ]))
    }

    private func shape(_ content: LayerContent) -> Path {
        LayerHitShape(content: content, referenceWidth: box.width).path(in: box)
    }

    /// The bug, stated: a thin diagonal used to swallow every tap in its
    /// bounding box, so a sticker sitting in an empty corner of that box could
    /// not be reached at all.
    @Test func aStrokeDoesNotClaimTheEmptyCornersOfItsBox() {
        let path = shape(diagonalDrawing())

        #expect(path.contains(CGPoint(x: 100, y: 100)), "the middle of the line is the line")
        #expect(!path.contains(CGPoint(x: 180, y: 20)), "the far corner is empty space")
        #expect(!path.contains(CGPoint(x: 20, y: 180)), "and so is the other one")
    }

    /// Thickened to exactly its drawn width, a hairline would be unhittable.
    @Test func eventTheThinnestStrokeKeepsAnHonestTouchWidth() {
        let path = shape(diagonalDrawing(width: .thin))
        let halfWidth = LayerHitShape.minimumTouchWidth / 2

        // Just off the line, inside the guaranteed band.
        #expect(path.contains(CGPoint(x: 100 + halfWidth / 2, y: 100)))
    }

    /// The three kinds that do fill their box must be untouched by this.
    @Test func everyOtherKindStaysTheWholeBox() {
        let kinds: [LayerContent] = [
            .photo(PhotoContent(photoID: id("p"))),
            .text(TextContent(content: "OOTD")),
            .sticker(StickerContent(emoji: "✨")),
        ]

        for kind in kinds {
            let path = shape(kind)
            #expect(path.contains(CGPoint(x: 180, y: 20)), "\(kind) should fill its box")
        }
    }

    @Test func aDrawingWithNoStrokesClaimsNothing() {
        let path = shape(.drawing(DrawingContent(strokes: [])))

        #expect(path.isEmpty)
        #expect(!path.contains(CGPoint(x: 100, y: 100)))
    }
}
