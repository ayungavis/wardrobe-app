import CoreGraphics
import Foundation
import Testing
@testable import WardrobeKit

/// The gesture recogniser decides which layer a touch grabbed, so this is the
/// part that has to be right — and, unlike gesture arbitration, it is arithmetic
/// and can be pinned down without a simulator.
struct CanvasHitTestTests {
    private let canvas = CGSize(width: 300, height: 600)
    private let size = CGSize(width: 100, height: 50)

    private func makeLayer(
        position: CGPoint = CGPoint(x: 0.5, y: 0.5),
        scale: CGFloat = 1,
        rotationDegrees: Double = 0
    ) -> EditorLayer {
        EditorLayer(
            content: .sticker(StickerContent(art: StickerArt(legacyEmoji: "✨"))),
            transform: ElementTransform(
                position: position, scale: scale, rotationDegrees: rotationDegrees
            )
        )
    }

    private func hit(_ point: CGPoint, _ layers: [EditorLayer]) -> UUID? {
        CanvasHitTest.layerID(
            at: point,
            in: EditorDocument(layers: layers),
            canvasSize: canvas,
            layerSizes: Dictionary(uniqueKeysWithValues: layers.map { ($0.id, size) })
        )
    }

    @Test func aTouchInsideTheLayerHitsIt() {
        let layer = makeLayer()

        #expect(hit(CGPoint(x: 150, y: 300), [layer]) == layer.id)
        #expect(hit(CGPoint(x: 190, y: 315), [layer]) == layer.id)
    }

    @Test func aTouchOutsideTheLayerMisses() {
        let layer = makeLayer()

        #expect(hit(CGPoint(x: 210, y: 300), [layer]) == nil)
        #expect(hit(CGPoint(x: 150, y: 340), [layer]) == nil)
    }

    /// The whole point of the feature: a layer scaled up catches touches its
    /// unscaled bounds would have missed.
    @Test func scaleWidensTheTouchArea() {
        let layer = makeLayer(scale: 2)

        #expect(hit(CGPoint(x: 210, y: 300), [layer]) == layer.id)
        #expect(hit(CGPoint(x: 260, y: 300), [layer]) == nil)
    }

    /// Rotating swaps which points are inside: this layer is wide and short, so
    /// a quarter turn makes it tall and narrow.
    @Test func rotationTurnsTheTouchAreaWithTheLayer() {
        let layer = makeLayer(rotationDegrees: 90)

        // Far to the side — inside before the turn, outside after it.
        #expect(hit(CGPoint(x: 190, y: 300), [layer]) == nil)
        // Far above — outside before the turn, inside after it.
        #expect(hit(CGPoint(x: 150, y: 340), [layer]) == layer.id)
    }

    /// Array order is z-order, so the last layer is drawn on top and must be the
    /// one a touch grabs.
    @Test func theTopmostOverlappingLayerWins() {
        let below = makeLayer()
        let above = makeLayer()

        #expect(hit(CGPoint(x: 150, y: 300), [below, above]) == above.id)
        #expect(hit(CGPoint(x: 150, y: 300), [above, below]) == below.id)
    }

    /// A layer SwiftUI has not measured yet has no shape to ask about, and
    /// guessing one would put its touch area in the wrong place.
    @Test func anUnmeasuredLayerCatchesNothing() {
        let layer = makeLayer()

        #expect(CanvasHitTest.layerID(
            at: CGPoint(x: 150, y: 300),
            in: EditorDocument(layers: [layer]),
            canvasSize: canvas,
            layerSizes: [:]
        ) == nil)
    }

    @Test func anUnmeasuredCanvasCatchesNothing() {
        let layer = makeLayer()

        #expect(CanvasHitTest.layerID(
            at: .zero,
            in: EditorDocument(layers: [layer]),
            canvasSize: .zero,
            layerSizes: [layer.id: size]
        ) == nil)
    }
}
