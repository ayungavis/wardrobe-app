import Foundation
import SwiftUI

public struct DrawingContent: Equatable, Codable, Sendable {
    public var strokes: [DrawingStroke]
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

public struct DrawingPoint: Equatable, Codable, Sendable {
    public var unitX: Double
    public var unitY: Double

    public init(unitX: Double, unitY: Double) {
        self.unitX = unitX
        self.unitY = unitY
    }
}

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

    public var contrastInk: Color {
        switch self {
        case .white, .yellow, .orange: .black
        case .black, .red, .green, .blue, .pink: .white
        }
    }

    public var name: String {
        LocalizedKey.resolve(Self.nameKey(for: self))
    }

    static func nameKey(for color: DrawingColor) -> String {
        "editor.drawing.color.\(color.rawValue)"
    }
}

public enum DrawingWidth: String, CaseIterable, Codable, Sendable {
    case thin, medium, thick

    public var ratio: Double {
        switch self {
        case .thin: 0.006
        case .medium: 0.012
        case .thick: 0.022
        }
    }

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
