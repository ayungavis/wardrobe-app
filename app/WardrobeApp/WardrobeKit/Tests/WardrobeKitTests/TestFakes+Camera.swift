import AVFoundation
import Foundation
@testable import WardrobeKit

@MainActor
final class FakeCameraService: CameraService {
    var permission: CameraPermission = .notDetermined
    var permissionAfterRequest: CameraPermission = .granted
    var captureResult: Result<Data, Error> = .success(Data([0x01]))
    var startError: Error?
    var toggleError: Error?
    private(set) var stopCount = 0
    private(set) var toggleCount = 0
    private(set) var isFlashOn = false
    private(set) var isUsingFrontCamera = false
    private(set) var displayZoomFactor: CGFloat = CameraZoom.standard
    private(set) var focusPoints: [CGPoint] = []
    private(set) var isConfigured = false

    /// Mirrors AVFCameraService: the device is only attached inside startSession,
    /// and until it is there is nothing to zoom, so a single option is reported.
    var zoomOptions: [CGFloat] {
        guard isConfigured else { return [CameraZoom.standard] }
        return isUsingFrontCamera ? [1, 2] : CameraZoom.presets
    }

    func toggleFlash() {
        isFlashOn.toggle()
    }

    func setDisplayZoom(_ factor: CGFloat) {
        displayZoomFactor = CameraZoom.clamp(factor, to: zoomOptions)
    }

    func focus(at point: CGPoint) {
        focusPoints.append(point)
    }

    var previewSession: AVCaptureSession? {
        nil
    }

    func requestPermission() async -> CameraPermission {
        permission = permissionAfterRequest
        return permission
    }

    func startSession() async throws {
        if let startError {
            throw startError
        }
        isConfigured = true
    }

    func stopSession() {
        stopCount += 1
    }

    func toggleCamera() async throws {
        if let toggleError {
            throw toggleError
        }
        toggleCount += 1
        isUsingFrontCamera.toggle()
        displayZoomFactor = CameraZoom.standard
    }

    func capturePhoto() async throws -> Data {
        try captureResult.get()
    }
}

// MARK: - Document fixtures and readers

extension EditorDocument {
    /// The same document with every photo layer pointed at `photoID`.
    func showingPhoto(_ photoID: UUID) -> EditorDocument {
        var copy = self
        copy.layers = layers.map { layer in
            guard case let .photo(content) = layer.content else { return layer }
            var updated = layer
            updated.content = .photo(PhotoContent(photoID: photoID, crop: content.crop))
            return updated
        }
        return copy
    }

    /// The bottom photo layer's crop — the single-photo shape most tests still
    /// speak in. Production says which layer it means (FR-093); a test with one
    /// photo has nothing to disambiguate.
    var firstPhotoCrop: CropSpec? {
        photoIDs.first
            .flatMap { photoLayerID(showing: $0) }
            .flatMap { crop(ofLayer: $0) }
    }

    /// The layer showing the first photo, for tests that need to name it.
    var firstPhotoLayerID: UUID? {
        photoIDs.first.flatMap { photoLayerID(showing: $0) }
    }

    /// Builds a document from the flat shape tests already read well in.
    /// Routed through the migration on purpose rather than reimplementing it —
    /// the migration has its own tests, so a break there fails loudly at the
    /// source instead of quietly here.
    static func fixture(
        photoID: UUID? = samplePhotoID,
        crop: CropSpec? = nil,
        texts: [TextItem] = [],
        stickers: [StickerItem] = [],
        background: CanvasBackground = .default
    ) -> EditorDocument {
        var document = EditorDocument(
            migrating: EditDraft(crop: crop, texts: texts, stickers: stickers),
            photoID: photoID
        )
        document.background = background
        return document
    }

    var textContents: [String] {
        layers.compactMap { layer in
            guard case let .text(text) = layer.content else { return nil }
            return text.content
        }
    }

    /// The flat projection, kept here because only tests still compare against
    /// the pre-canvas shape — production reads `EditorLayer.textDraft`.
    var textItems: [TextItem] {
        layers.compactMap { layer in
            guard case let .text(text) = layer.content else { return nil }
            return TextItem(
                id: layer.id,
                content: text.content,
                position: layer.transform.position,
                scale: layer.transform.scale,
                rotationDegrees: layer.transform.rotationDegrees,
                colorName: text.colorName,
                hasBackground: text.backgroundStyle == .solid,
                fontName: text.fontName,
                alignmentName: text.alignmentName
            )
        }
    }

    var stickerItems: [StickerItem] {
        layers.compactMap { layer -> StickerItem? in
            guard case let .sticker(sticker) = layer.content,
                  case let .emoji(glyph)? = sticker.art.design
            else {
                return nil
            }
            return StickerItem(
                id: layer.id,
                emoji: glyph,
                position: layer.transform.position,
                scale: layer.transform.scale,
                rotationDegrees: layer.transform.rotationDegrees
            )
        }
    }

    var stickerEmojis: [String] {
        stickerItems.map(\.emoji)
    }

    var stickerArts: [StickerArt] {
        layers.compactMap { layer in
            guard case let .sticker(sticker) = layer.content else { return nil }
            return sticker.art
        }
    }
}
