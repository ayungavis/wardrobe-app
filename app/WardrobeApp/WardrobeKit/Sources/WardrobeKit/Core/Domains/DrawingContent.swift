import Foundation

/// Freehand strokes on the canvas (PRD FR-088's drawing layer).
///
/// Every coordinate is unit space, so a stroke drawn on one phone lands in the
/// same place on another — the same rule the rest of the document follows.
public struct DrawingContent: Equatable, Codable, Sendable {
    public var strokes: [DrawingStroke]

    public static let empty = DrawingContent(strokes: [])

    public init(strokes: [DrawingStroke]) {
        self.strokes = strokes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        strokes = try container.decodeIfPresent([DrawingStroke].self, forKey: .strokes) ?? []
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
}

public enum DrawingWidth: String, CaseIterable, Codable, Sendable {
    case thin, medium, thick

    /// Fraction of the canvas width, so a stroke keeps its weight at any size.
    public var ratio: Double {
        switch self {
        case .thin: 0.008
        case .medium: 0.02
        case .thick: 0.045
        }
    }
}
