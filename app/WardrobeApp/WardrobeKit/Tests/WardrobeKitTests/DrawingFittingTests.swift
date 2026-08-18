import CoreGraphics
import Foundation
import Testing
@testable import WardrobeKit

/// Trimming a session to its marks is what makes a drawing a layer rather than
/// a canvas-sized sheet. Pure arithmetic, so it is checked here rather than
/// with a finger.
struct DrawingFittingTests {
    private let canvas = CGSize(width: 360, height: 640)

    private func stroke(_ points: [(Double, Double)], width: DrawingWidth = .medium) -> DrawingStroke {
        DrawingStroke(points: points.map { DrawingPoint(unitX: $0.0, unitY: $0.1) }, width: width)
    }

    @Test func anEmptySessionCommitsNothing() {
        #expect(DrawingFitting.fit(.empty, canvasSize: canvas) == nil)
        #expect(DrawingFitting.fit(DrawingContent(strokes: [stroke([])]), canvasSize: canvas) == nil)
    }

    @Test func aCanvasWithNoSizeYetFitsNothing() {
        let content = DrawingContent(strokes: [stroke([(0.4, 0.4), (0.6, 0.6)])])

        #expect(DrawingFitting.fit(content, canvasSize: .zero) == nil)
    }

    /// The heart of it: a doodle in one corner becomes a small layer sitting on
    /// that corner, not a full-canvas layer that happens to be mostly empty.
    @Test func theLayerShrinksToTheMarksAndSitsWhereTheyWere() throws {
        let content = DrawingContent(strokes: [stroke([(0.2, 0.1), (0.3, 0.2)])])

        let fitted = try #require(DrawingFitting.fit(content, canvasSize: canvas))

        #expect(fitted.content.widthRatio < 0.25)
        #expect(fitted.content.heightRatio < 0.25)
        // Centre of the marks: (0.25, 0.15) in canvas units.
        #expect(abs(fitted.transform.position.x - 0.25) < 0.01)
        #expect(abs(fitted.transform.position.y - 0.15) < 0.01)
    }

    @Test func pointsAreRenormalisedIntoTheBox() throws {
        let content = DrawingContent(strokes: [stroke([(0.2, 0.1), (0.3, 0.2)])])

        let fitted = try #require(DrawingFitting.fit(content, canvasSize: canvas))
        let points = try #require(fitted.content.strokes.first?.points)

        for point in points {
            #expect(point.unitX >= 0 && point.unitX <= 1)
            #expect(point.unitY >= 0 && point.unitY <= 1)
        }
        #expect(points[0].unitX < points[1].unitX)
        #expect(points[0].unitY < points[1].unitY)
    }

    /// Fitting must put the marks back exactly where they were drawn.
    @Test func fittingIsAMoveNotAShift() throws {
        let content = DrawingContent(strokes: [stroke([(0.2, 0.1), (0.3, 0.2), (0.25, 0.3)])])

        let fitted = try #require(DrawingFitting.fit(content, canvasSize: canvas))
        let box = CGRect(
            x: (fitted.transform.position.x - fitted.content.widthRatio / 2) * canvas.width,
            y: (fitted.transform.position.y - fitted.content.heightRatio / 2) * canvas.height,
            width: fitted.content.widthRatio * canvas.width,
            height: fitted.content.heightRatio * canvas.height
        )
        let points = try #require(fitted.content.strokes.first?.points)

        for (index, point) in points.enumerated() {
            let restoredX = (box.minX + point.unitX * box.width) / canvas.width
            let restoredY = (box.minY + point.unitY * box.height) / canvas.height
            let original = content.strokes[0].points[index]
            #expect(abs(restoredX - original.unitX) < 0.001)
            #expect(abs(restoredY - original.unitY) < 0.001)
        }
    }

    /// A fat line drawn along the edge of its own bounds would be sliced in
    /// half without the stroke's radius in the box.
    @Test func theBoxGrowsWithTheWeightOfTheLine() throws {
        let points = [(0.5, 0.5), (0.6, 0.5)]

        let thin = try #require(DrawingFitting.fit(
            DrawingContent(strokes: [stroke(points, width: .thin)]), canvasSize: canvas
        ))
        let thick = try #require(DrawingFitting.fit(
            DrawingContent(strokes: [stroke(points, width: .thick)]), canvasSize: canvas
        ))

        #expect(thick.content.heightRatio > thin.content.heightRatio)
    }

    /// A tap is a dot, and a dot still needs a box you can see and grab.
    @Test func aSinglePointStillGetsAVisibleBox() throws {
        let fitted = try #require(DrawingFitting.fit(
            DrawingContent(strokes: [stroke([(0.5, 0.5)])]), canvasSize: canvas
        ))

        #expect(fitted.content.widthRatio > 0)
        #expect(fitted.content.heightRatio > 0)
    }

    @Test func theBoxNeverLeavesTheCanvas() throws {
        let fitted = try #require(DrawingFitting.fit(
            DrawingContent(strokes: [stroke([(0, 0), (1, 1)], width: .thick)]), canvasSize: canvas
        ))

        #expect(fitted.content.widthRatio <= 1)
        #expect(fitted.content.heightRatio <= 1)
    }
}
