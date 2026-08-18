import CoreGraphics
import Foundation
import Testing
@testable import WardrobeKit

/// The drawing tool's contract: the document is untouched until Done, and one
/// session becomes exactly one layer.
@MainActor
struct EditorDrawingToolTests {
    private let canvas = CGSize(width: 360, height: 640)

    private func points(_ pairs: [(Double, Double)]) -> [DrawingPoint] {
        pairs.map { DrawingPoint(unitX: $0.0, unitY: $0.1) }
    }

    private func session(of sut: EditorViewModel) -> DrawingContent? {
        guard case let .drawing(content) = sut.activeTool else { return nil }
        return content
    }

    @Test func beginningClearsTheSelectionAndPutsThePenBack() throws {
        let sut = try makeEditorSUT()
        sut.select(UUID())
        sut.toggleEraser()

        sut.beginDrawing()

        #expect(sut.selectedLayerID == nil)
        #expect(!sut.pen.isErasing)
        #expect(session(of: sut) == .empty)
    }

    /// Strokes accumulate in the tool, not the document — which is what makes
    /// cancelling free (FR-019).
    @Test func strokesAccumulateWithoutTouchingTheDocument() throws {
        let activeRepository = InMemoryActiveChallengeRepository()
        let sut = try makeEditorSUT(activeRepository: activeRepository)
        let before = sut.document

        sut.beginDrawing()
        sut.finishStroke(points([(0.2, 0.2), (0.3, 0.3)]), canvasSize: canvas)
        sut.finishStroke(points([(0.5, 0.5), (0.6, 0.6)]), canvasSize: canvas)

        #expect(session(of: sut)?.strokes.count == 2)
        #expect(sut.document == before)
    }

    @Test func aStrokeWithNothingDrawableIsIgnored() throws {
        let sut = try makeEditorSUT()
        sut.beginDrawing()

        sut.finishStroke([], canvasSize: canvas)
        sut.finishStroke(points([(.nan, .nan)]), canvasSize: canvas)

        #expect(session(of: sut)?.strokes.isEmpty == true)
    }

    @Test func theEraserLiftsAStrokeItCrosses() throws {
        let sut = try makeEditorSUT()
        sut.beginDrawing()
        sut.finishStroke(points([(0.5, 0.5), (0.51, 0.5)]), canvasSize: canvas)

        sut.toggleEraser()
        sut.finishStroke(points([(0.5, 0.5)]), canvasSize: canvas)

        #expect(session(of: sut)?.strokes.isEmpty == true)
    }

    /// Reaching for a colour is asking to draw, not to keep erasing.
    @Test func pickingAColourPutsThePenBack() throws {
        let sut = try makeEditorSUT()
        sut.beginDrawing()
        sut.toggleEraser()

        sut.setPen(color: .blue)

        #expect(!sut.pen.isErasing)
        #expect(sut.pen.color == .blue)
    }

    /// The pen describes the hand, not the picture, so it survives the session.
    @Test func thePenSurvivesBetweenSessions() throws {
        let sut = try makeEditorSUT()
        sut.beginDrawing()
        sut.setPen(color: .green)
        sut.setPen(width: .thick)
        sut.cancelTool()

        sut.beginDrawing()

        #expect(sut.pen.color == .green)
        #expect(sut.pen.width == .thick)
    }

    @Test func clearingEmptiesTheSessionWithoutLeavingTheTool() throws {
        let sut = try makeEditorSUT()
        sut.beginDrawing()
        sut.finishStroke(points([(0.2, 0.2), (0.3, 0.3)]), canvasSize: canvas)

        sut.clearDrawing()

        #expect(session(of: sut)?.strokes.isEmpty == true)
    }

    @Test func cancellingDiscardsTheWholeSession() throws {
        let sut = try makeEditorSUT()
        let before = sut.document
        sut.beginDrawing()
        sut.finishStroke(points([(0.2, 0.2), (0.3, 0.3)]), canvasSize: canvas)

        sut.cancelTool()

        #expect(sut.activeTool == nil)
        #expect(sut.document == before)
    }

    @Test func oneSessionBecomesExactlyOneSelectedLayer() throws {
        let activeRepository = InMemoryActiveChallengeRepository()
        let sut = try makeEditorSUT(activeRepository: activeRepository)
        let layersBefore = sut.document.layers.count

        sut.beginDrawing()
        sut.finishStroke(points([(0.2, 0.2), (0.3, 0.3)]), canvasSize: canvas)
        sut.finishStroke(points([(0.5, 0.5), (0.6, 0.6)]), canvasSize: canvas)
        sut.finishDrawing(canvasSize: canvas)

        #expect(sut.document.layers.count == layersBefore + 1)
        #expect(sut.activeTool == nil)
        #expect(sut.selectedLayerID == sut.document.layers.last?.id)
        #expect(activeRepository.stored?.document.layers.count == layersBefore + 1)

        guard case let .drawing(drawing) = sut.document.layers.last?.content else {
            Issue.record("expected a drawing layer")
            return
        }
        #expect(drawing.strokes.count == 2)
        // Trimmed to its marks, not left the size of the canvas.
        #expect(drawing.widthRatio < 1)
    }

    @Test func anEmptySessionCommitsNoLayer() throws {
        let sut = try makeEditorSUT()
        let layersBefore = sut.document.layers.count

        sut.beginDrawing()
        sut.finishDrawing(canvasSize: canvas)

        #expect(sut.document.layers.count == layersBefore)
        #expect(sut.activeTool == nil)
    }
}
