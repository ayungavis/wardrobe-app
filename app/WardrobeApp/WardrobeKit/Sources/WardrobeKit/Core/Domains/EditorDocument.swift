import CoreGraphics
import Foundation

/// The layered story canvas (PRD FR-084): ordered layers over a 9:16 canvas,
/// each one non-destructive instructions rather than pixels.
///
/// Everything here is stored, synced after ✓, and reopened for re-editing on
/// another phone — so its shape is hard to change later. Two consequences run
/// through the whole file:
///
/// - **Geometry is unit space (0…1), never points.** A point offset means
///   nothing on a phone with a different screen than the one that authored it,
///   and FR-096 requires documents to restore on a second device.
/// - **Nothing here is UI state.** Selection, undo history, and the tool in hand
///   belong to the view model; syncing them would carry meaningless state to
///   another device.
public struct EditorDocument: Equatable, Sendable {
    /// Bumped when the shape below changes in a way an older app cannot read.
    /// Stored from the first release, because a document outlives the build
    /// that wrote it (FR-098).
    public static let currentSchemaVersion = 1

    public let id: UUID
    public private(set) var schemaVersion: Int
    /// Bottom to top. Array order *is* z-order — one ordering, so it cannot
    /// disagree with itself.
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

    /// A fresh document: one photo layer, filling the canvas.
    public init(photoID: String, crop: CropSpec? = nil) {
        self.init(layers: [EditorLayer(content: .photo(PhotoContent(photoID: photoID, crop: crop)))])
    }
}

// MARK: - Migration

public extension EditorDocument {
    /// Reads a flat `EditDraft` as a document.
    ///
    /// Not a convenience: drafts are already persisted inside `ActiveChallenge`
    /// and `CompletedChallenge` on people's phones, so without this path the
    /// port would erase work they have already done.
    ///
    /// Order is **read off the existing renderers, not chosen**: both
    /// `EditorCanvasView` and `ExportCompositionView` draw stickers first and
    /// texts over them, so that is the z-order a migrated draft must keep.
    /// Getting it backwards would silently reshuffle work people have already
    /// done.
    ///
    /// Ids carry across, so a layer is still the same thing it was in the
    /// draft — that is what makes the projection back to `EditDraft` a
    /// round trip rather than a copy.
    ///
    /// `photoID` is optional because a draft can exist before a capture does;
    /// with no photo there is simply no photo layer to build.
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

    /// Lenient *within* a version, unforgiving *across* one.
    ///
    /// Fields added later may default. A document written by a newer app may
    /// not: decoding it would quietly drop layer kinds this build has never
    /// heard of, and FR-098 forbids dropping or rewriting unknown content. It
    /// throws instead, so the editor can send the user to update the app while
    /// their work stays untouched.
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
    /// Locked layers still render and export; they just ignore canvas gestures
    /// until unlocked (FR-086).
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

/// Where a layer sits, in unit space. The layer owns this; its content does
/// not, so a position can never be stored in two places and disagree.
public struct ElementTransform: Equatable, Codable, Sendable {
    /// Centre of the layer, 0…1 across the canvas.
    public var position: CGPoint
    public var scale: CGFloat
    public var rotationDegrees: Double

    public static let identity = ElementTransform()

    /// One range for every layer kind. The flat draft clamped text to 0.5…3 and
    /// stickers to 0.5…4; a single transform shared by photos, text, stickers,
    /// and drawings gets a single range rather than a third one.
    ///
    /// It lives on the model, not on the canvas, because it is what makes a
    /// stored document sane — whoever writes the transform, the bound holds.
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

// MARK: - Content

/// The four layer kinds. An enum with payloads rather than a struct of
/// optionals: a layer that is both a sticker and a drawing cannot be written.
///
/// FR-084 fixes this set — it is not extensible by users.
public enum LayerContent: Equatable, Sendable {
    case photo(PhotoContent)
    case text(TextContent)
    case sticker(StickerContent)
    case drawing(DrawingContent)
}

extension LayerContent: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, value
    }

    private enum Kind: String, Codable {
        case photo, text, sticker, drawing
    }

    private var kind: Kind {
        switch self {
        case .photo: .photo
        case .text: .text
        case .sticker: .sticker
        case .drawing: .drawing
        }
    }

    /// Written by hand rather than synthesized. The compiler encodes enum
    /// payloads under generated labels (`_0`), and this shape is stored on
    /// people's phones and synced to the server — a format that outlives many
    /// builds cannot rest on a name the compiler is free to change.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // An unrecognised kind means the document knows something this build
        // does not; say that, rather than surfacing a raw decoding error
        // (FR-098).
        guard let kind = try? container.decode(Kind.self, forKey: .kind) else {
            throw AppError.documentFromNewerApp
        }

        switch kind {
        case .photo: self = try .photo(container.decode(PhotoContent.self, forKey: .value))
        case .text: self = try .text(container.decode(TextContent.self, forKey: .value))
        case .sticker: self = try .sticker(container.decode(StickerContent.self, forKey: .value))
        case .drawing: self = try .drawing(container.decode(DrawingContent.self, forKey: .value))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)

        switch self {
        case let .photo(content): try container.encode(content, forKey: .value)
        case let .text(content): try container.encode(content, forKey: .value)
        case let .sticker(content): try container.encode(content, forKey: .value)
        case let .drawing(content): try container.encode(content, forKey: .value)
        }
    }
}

/// The cropped capture inside its polaroid frame (FR-092). Only the id and the
/// crop are stored; the pixels stay in the photo repository, untouched.
public struct PhotoContent: Equatable, Codable, Sendable {
    public let photoID: String
    public var crop: CropSpec?

    public init(photoID: String, crop: CropSpec? = nil) {
        self.photoID = photoID
        self.crop = crop
    }
}

public struct TextContent: Equatable, Codable, Sendable {
    public var content: String
    public var colorName: String
    public var hasBackground: Bool
    public var fontName: String
    public var alignmentName: String

    public var textColor: TextColor {
        TextColor(rawValue: colorName) ?? .white
    }

    public var fontStyle: TextFontStyle {
        TextFontStyle(rawValue: fontName) ?? .classic
    }

    public var alignmentStyle: TextAlignmentStyle {
        TextAlignmentStyle(rawValue: alignmentName) ?? .center
    }

    public init(
        content: String,
        colorName: String = TextColor.white.rawValue,
        hasBackground: Bool = false,
        fontName: String = TextFontStyle.classic.rawValue,
        alignmentName: String = TextAlignmentStyle.center.rawValue
    ) {
        self.content = content
        self.colorName = colorName
        self.hasBackground = hasBackground
        self.fontName = fontName
        self.alignmentName = alignmentName
    }

    /// Carries a flat draft's text across without losing its styling.
    public init(_ item: TextItem) {
        self.init(
            content: item.content,
            colorName: item.colorName,
            hasBackground: item.hasBackground,
            fontName: item.fontName,
            alignmentName: item.alignmentName
        )
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        content = try container.decode(String.self, forKey: .content)
        colorName = try container.decodeIfPresent(String.self, forKey: .colorName) ?? TextColor.white.rawValue
        hasBackground = try container.decodeIfPresent(Bool.self, forKey: .hasBackground) ?? false
        fontName = try container.decodeIfPresent(String.self, forKey: .fontName)
            ?? TextFontStyle.classic.rawValue
        alignmentName = try container.decodeIfPresent(String.self, forKey: .alignmentName)
            ?? TextAlignmentStyle.center.rawValue
    }
}

public struct StickerContent: Equatable, Codable, Sendable {
    public var emoji: String

    public init(emoji: String) {
        self.emoji = emoji
    }
}
