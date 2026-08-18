import Foundation
import SwiftUI

/// Freehand strokes on the canvas (PRD FR-088's drawing layer).
///
/// Every coordinate is unit space, so a stroke drawn on one phone lands in the
/// same place on another — the same rule the rest of the document follows.
public struct DrawingContent: Equatable, Codable, Sendable {
    public var strokes: [DrawingStroke]
    /// How much of the canvas this layer's box covers. A finished drawing is
    /// trimmed to its own content, so a doodle in one corner becomes an object
    /// the size of the doodle — selectable and draggable like any other layer,
    /// instead of a canvas-sized sheet swallowing every tap beneath it.
    ///
    /// Points are 0…1 **within that box**, which is also what keeps a
    /// transform from compounding with the coordinates.
    public var widthRatio: Double
    public var heightRatio: Double

    public static let empty = DrawingContent(strokes: [])

    public init(strokes: [DrawingStroke], widthRatio: Double = 1, heightRatio: Double = 1) {
        self.strokes = strokes
        self.widthRatio = widthRatio
        self.heightRatio = heightRatio
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        strokes = try container.decodeIfPresent([DrawingStroke].self, forKey: .strokes) ?? []
        widthRatio = try container.decodeIfPresent(Double.self, forKey: .widthRatio) ?? 1
        heightRatio = try container.decodeIfPresent(Double.self, forKey: .heightRatio) ?? 1
    }

    public var isEmpty: Bool {
        strokes.isEmpty
    }

    /// Applies one finished drag. Nil when the drag changed nothing — an
    /// eraser that crossed empty space, or a stroke with no drawable points.
    ///
    /// Lives on the content rather than the view model because it is a rule
    /// about what a drawing *is*, and here it can be tested without a finger.
    public func applying(
        _ stroke: DrawingStroke,
        pen: DrawingPen,
        heightOverWidth: Double
    ) -> DrawingContent? {
        guard let stroke = stroke.sanitized() else { return nil }

        guard pen.isErasing else {
            var extended = self
            extended.strokes.append(stroke)
            return extended
        }

        return erasingStrokes(
            touching: stroke.points,
            radius: pen.width.eraserRadius,
            heightOverWidth: heightOverWidth
        )
    }

    /// Drops every stroke the eraser touched. Nil when it touched nothing, so
    /// the caller can tell "erased" from "missed" without comparing documents.
    ///
    /// The eraser removes whole strokes rather than cutting geometry: a stroke
    /// is an instruction, and half an instruction is not a thing the document
    /// can hold.
    ///
    /// `heightOverWidth` un-does the anisotropic normalisation — x is a
    /// fraction of the width and y of the height, so without it the eraser
    /// would be an ellipse.
    public func erasingStrokes(
        touching eraserPoints: [DrawingPoint],
        radius: Double,
        heightOverWidth: Double
    ) -> DrawingContent? {
        guard !eraserPoints.isEmpty, radius > 0 else { return nil }

        let kept = strokes.filter { stroke in
            !stroke.points.contains { strokePoint in
                eraserPoints.contains { eraserPoint in
                    let horizontal = strokePoint.unitX - eraserPoint.unitX
                    let vertical = (strokePoint.unitY - eraserPoint.unitY) * heightOverWidth
                    return horizontal * horizontal + vertical * vertical <= radius * radius
                }
            }
        }

        guard kept.count != strokes.count else { return nil }

        var erased = self
        erased.strokes = kept
        return erased
    }
}

public struct DrawingStroke: Identifiable, Equatable, Codable, Sendable {
    /// A finger can emit thousands of points a second; past this the extra ones
    /// cost storage and sync bandwidth without being visible.
    public static let maximumPointCount = 512

    public let id: UUID
    public var points: [DrawingPoint]
    public var colorName: String
    public var widthName: String

    public var color: DrawingColor {
        DrawingColor(rawValue: colorName) ?? .black
    }

    public var width: DrawingWidth {
        DrawingWidth(rawValue: widthName) ?? .medium
    }

    public init(
        id: UUID = UUID(),
        points: [DrawingPoint],
        color: DrawingColor = .black,
        width: DrawingWidth = .medium
    ) {
        self.id = id
        self.points = points
        colorName = color.rawValue
        widthName = width.rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        points = try container.decodeIfPresent([DrawingPoint].self, forKey: .points) ?? []
        colorName = try container.decodeIfPresent(String.self, forKey: .colorName)
            ?? DrawingColor.black.rawValue
        widthName = try container.decodeIfPresent(String.self, forKey: .widthName)
            ?? DrawingWidth.medium.rawValue
    }

    /// Drops what cannot be drawn and bounds what would be wasteful: NaN or
    /// infinite points vanish, stray points are pulled back onto the canvas, and
    /// the count is capped. A stroke with nothing left is nil rather than an
    /// invisible entry that still costs bytes forever.
    public func sanitized(maximumPointCount: Int = DrawingStroke.maximumPointCount) -> DrawingStroke? {
        let cleaned = points
            .prefix(maximumPointCount)
            .compactMap { point -> DrawingPoint? in
                guard point.unitX.isFinite, point.unitY.isFinite else { return nil }
                return DrawingPoint(
                    unitX: min(max(point.unitX, 0), 1),
                    unitY: min(max(point.unitY, 0), 1)
                )
            }
        guard !cleaned.isEmpty else { return nil }

        var sanitized = self
        sanitized.points = cleaned
        return sanitized
    }
}

/// A point in unit space, 0…1 across the canvas.
///
/// Named for the space rather than `x`/`y`: every coordinate in a document is a
/// fraction of the canvas, and a reader should not have to check.
public struct DrawingPoint: Equatable, Codable, Sendable {
    public var unitX: Double
    public var unitY: Double

    public init(unitX: Double, unitY: Double) {
        self.unitX = unitX
        self.unitY = unitY
    }
}

/// Content palettes, not design-system tokens — these are choices the user
/// makes about their picture, the way `TextColor` already is.
public enum DrawingColor: String, CaseIterable, Codable, Sendable {
    case black, white, red, orange, yellow, green, blue, pink

    public var color: Color {
        switch self {
        case .black: .black
        case .white: .white
        case .red: Color(red: 0.96, green: 0.20, blue: 0.24)
        case .orange: Color(red: 1, green: 0.47, blue: 0.10)
        case .yellow: Color(red: 1, green: 0.84, blue: 0.12)
        case .green: Color(red: 0.20, green: 0.76, blue: 0.38)
        case .blue: Color(red: 0.16, green: 0.52, blue: 1)
        case .pink: Color(red: 0.95, green: 0.36, blue: 0.65)
        }
    }

    /// Ink that reads on top of this colour — a border around the swatch, or a
    /// checkmark inside it.
    ///
    /// One table, not two: the prototype had separate rules for the border and
    /// the checkmark that disagreed only about orange, which is one question
    /// answered twice.
    public var contrastInk: Color {
        switch self {
        case .white, .yellow, .orange: .black
        case .black, .red, .green, .blue, .pink: .white
        }
    }

    public var name: String {
        LocalizedKey.resolve(Self.nameKey(for: self))
    }

    /// Assembled at runtime, so the extractor prunes these as stale unless they
    /// are pinned `"extractionState": "manual"`. A test fails if that pin goes.
    static func nameKey(for color: DrawingColor) -> String {
        "editor.drawing.color.\(color.rawValue)"
    }
}

public enum DrawingWidth: String, CaseIterable, Codable, Sendable {
    case thin, medium, thick

    /// Fraction of the canvas width, so a stroke keeps its weight at any size —
    /// on screen and at export, where the canvas is nearly three times wider.
    public var ratio: Double {
        switch self {
        case .thin: 0.006
        case .medium: 0.012
        case .thick: 0.022
        }
    }

    /// How far the eraser reaches, in the same width-relative units.
    ///
    /// The floor exists so a hairline is still catchable, but it is deliberately
    /// low: the prototype's 0.025 swallowed two of the three widths, leaving a
    /// control that did nothing for two of its values.
    public var eraserRadius: Double {
        max(ratio * 1.8, 0.010)
    }

    public var name: String {
        LocalizedKey.resolve(Self.nameKey(for: self))
    }

    static func nameKey(for width: DrawingWidth) -> String {
        "editor.drawing.width.\(width.rawValue)"
    }
}
