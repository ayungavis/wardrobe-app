import CoreGraphics
import Foundation

public struct EditorDocument: Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let id: UUID
    public private(set) var schemaVersion: Int
    public var layers: [EditorLayer]
    public var background: CanvasBackground

    public init(
        id: UUID = UUID(),
        schemaVersion: Int = EditorDocument.currentSchemaVersion,
        layers: [EditorLayer],
        background: CanvasBackground = .white
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.layers = layers
        self.background = background
    }

    public init(photoID: String, crop: CropSpec? = nil) {
        self.init(layers: [EditorLayer(content: .photo(PhotoContent(photoID: photoID, crop: crop)))])
    }
}

// MARK: - Migration

public extension EditorDocument {
    init(migrating draft: EditDraft, photoID: String?) {
        var layers: [EditorLayer] = []

        if let photoID {
            layers.append(EditorLayer(content: .photo(PhotoContent(photoID: photoID, crop: draft.crop))))
        }

        layers += draft.stickers.map { sticker in
            EditorLayer(
                id: sticker.id,
                content: .sticker(StickerContent(emoji: sticker.emoji)),
                transform: ElementTransform(
                    position: sticker.position,
                    scale: sticker.scale,
                    rotationDegrees: sticker.rotationDegrees
                )
            )
        }

        layers += draft.texts.map { text in
            EditorLayer(
                id: text.id,
                content: .text(TextContent(text)),
                transform: ElementTransform(
                    position: text.position,
                    scale: text.scale,
                    rotationDegrees: text.rotationDegrees
                )
            )
        }

        self.init(layers: layers)
    }
}

// MARK: - Codable

extension EditorDocument: Codable {
    enum CodingKeys: String, CodingKey {
        case id, schemaVersion, layers, background
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        guard version <= Self.currentSchemaVersion else {
            throw AppError.documentFromNewerApp
        }

        id = try container.decode(UUID.self, forKey: .id)
        schemaVersion = version
        layers = try container.decodeIfPresent([EditorLayer].self, forKey: .layers) ?? []
        background = try container.decodeIfPresent(CanvasBackground.self, forKey: .background) ?? .white
    }
}

// MARK: - Layer

public struct EditorLayer: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public var content: LayerContent
    public var transform: ElementTransform
    public var isLocked: Bool

    public init(
        id: UUID = UUID(),
        content: LayerContent,
        transform: ElementTransform = .identity,
        isLocked: Bool = false
    ) {
        self.id = id
        self.content = content
        self.transform = transform
        self.isLocked = isLocked
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        content = try container.decode(LayerContent.self, forKey: .content)
        transform = try container.decodeIfPresent(ElementTransform.self, forKey: .transform) ?? .identity
        isLocked = try container.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
    }
}

public struct ElementTransform: Equatable, Codable, Sendable {
    public var position: CGPoint
    public var scale: CGFloat
    public var rotationDegrees: Double

    public static let identity = ElementTransform()

    public static let scaleRange: ClosedRange<CGFloat> = 0.3 ... 5

    public static func clampedScale(_ scale: CGFloat) -> CGFloat {
        guard scale.isFinite else { return 1 }
        return min(max(scale, scaleRange.lowerBound), scaleRange.upperBound)
    }

    public func clamped() -> ElementTransform {
        var clamped = self
        clamped.scale = Self.clampedScale(scale)
        return clamped
    }

    public init(
        position: CGPoint = CGPoint(x: 0.5, y: 0.5),
        scale: CGFloat = 1,
        rotationDegrees: Double = 0
    ) {
        self.position = position
        self.scale = scale
        self.rotationDegrees = rotationDegrees
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        position = try container.decodeIfPresent(CGPoint.self, forKey: .position)
            ?? CGPoint(x: 0.5, y: 0.5)
        scale = try container.decodeIfPresent(CGFloat.self, forKey: .scale) ?? 1
        rotationDegrees = try container.decodeIfPresent(Double.self, forKey: .rotationDegrees) ?? 0
    }
}
