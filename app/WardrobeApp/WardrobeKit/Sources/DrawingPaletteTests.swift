import Foundation
import Testing
@testable import WardrobeKit

/// FR-019's pen: colour, width, and an eraser that responds to both.
struct DrawingPaletteTests {
    // MARK: The eraser

    private func points(_ pairs: [(Double, Double)]) -> [DrawingPoint] {
        pairs.map { DrawingPoint(unitX: $0.0, unitY: $0.1) }
    }

    @Test func theEraserLiftsOnlyTheStrokesItCrossed() throws {
        let hit = DrawingStroke(points: points([(0.5, 0.5)]))
        let missed = DrawingStroke(points: points([(0.1, 0.1)]))
        let content = DrawingContent(strokes: [hit, missed])

        let erased = try #require(content.erasingStrokes(
            touching: points([(0.5, 0.5)]), radius: 0.02, heightOverWidth: 16.0 / 9
        ))

        #expect(erased.strokes.map(\.id) == [missed.id])
    }

    /// Nil rather than an unchanged copy, so the caller can tell a miss from a
    /// hit without comparing documents.
    @Test func erasingEmptySpaceReportsThatNothingHappened() {
        let content = DrawingContent(strokes: [DrawingStroke(points: points([(0.9, 0.9)]))])

        #expect(content.erasingStrokes(
            touching: points([(0.1, 0.1)]), radius: 0.02, heightOverWidth: 16.0 / 9
        ) == nil)
    }

    /// The divergence this guards: the prototype's radius floor swallowed two of
    /// the three widths, leaving a control that did nothing for two of its
    /// values.
    @Test func everyWidthGivesTheEraserADifferentReach() {
        let radii = DrawingWidth.allCases.map(\.eraserRadius)

        #expect(Set(radii).count == DrawingWidth.allCases.count)
        #expect(radii == radii.sorted())
    }

    /// Ratios are what a stroke actually looks like; drifting them silently
    /// re-weights every drawing already made.
    @Test func strokeWeightsAreStable() {
        #expect(DrawingWidth.thin.ratio == 0.006)
        #expect(DrawingWidth.medium.ratio == 0.012)
        #expect(DrawingWidth.thick.ratio == 0.022)
    }

    @Test func theStoredPaletteNamesAreUnchanged() {
        #expect(DrawingColor.allCases.map(\.rawValue) == [
            "black", "white", "red", "orange", "yellow", "green", "blue", "pink",
        ])
        #expect(DrawingWidth.allCases.map(\.rawValue) == ["thin", "medium", "thick"])
    }

    // MARK: Names in the catalogue

    @Test func everyColourAndWidthHasATranslatedPinnedName() throws {
        let url = try #require(Bundle.module.url(forResource: "Localizable", withExtension: "xcstrings"))
        let catalogue = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        let strings = try #require((catalogue as? [String: Any])?["strings"] as? [String: Any])

        let keys = DrawingColor.allCases.map { DrawingColor.nameKey(for: $0) }
            + DrawingWidth.allCases.map { DrawingWidth.nameKey(for: $0) }

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
