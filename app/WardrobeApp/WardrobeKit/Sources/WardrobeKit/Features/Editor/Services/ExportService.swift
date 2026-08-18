import CoreFoundation
import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

// ponytail: a pure function, so no protocol — add one when a second
// implementation or a test seam actually needs it.
public enum ExportService {
    // ponytail: export capped at 4096px long edge — plenty for sharing;
    // raise when a print/quality requirement appears.
    static let maxOutputPixel: CGFloat = 4096

    /// Decodes to pixels (drops all source metadata), applies the crop, then
    /// composes the story frame — the very same 9:16 layout the editor canvas
    /// shows — and re-encodes through `CGImageDestination` writing zero source
    /// properties. Save and Share both come through here, so the file always
    /// matches the preview.
    ///
    /// Split in three because only the middle step has to be on the main
    /// actor: `ImageRenderer` is main-actor-bound, but decoding a 12-megapixel
    /// source and deflating the JPEG are not, and running them there is what
    /// made exporting stall the canvas (PRD §17 asks for non-blocking
    /// progress).
    public static func render(original: Data, document: EditorDocument) async throws -> Data {
        let photo = try await prepare(original: original, crop: document.photoCrop)
        let rendered = try await rasterize(document: document, photo: photo)
        return try await encode(rendered)
    }

    /// `@concurrent` rather than bare `nonisolated`: a nonisolated async
    /// function stays on the caller's actor (SE-0461), and every caller here is
    /// `@MainActor`, so without it this would not move at all.
    @concurrent
    static func prepare(original: Data, crop: CropSpec?) async throws -> CGImage {
        // Orientation-corrected, metadata-free decode.
        guard let image = ImageDecoding.downsampledImage(from: original, maxPixel: maxOutputPixel) else {
            throw AppError.exportFailed
        }
        guard let crop else { return image }

        let rect = CGRect(
            x: crop.rect.origin.x * CGFloat(image.width),
            y: crop.rect.origin.y * CGFloat(image.height),
            width: crop.rect.width * CGFloat(image.width),
            height: crop.rect.height * CGFloat(image.height)
        ).integral
        guard let cropped = image.cropping(to: rect) else { throw AppError.exportFailed }
        return cropped
    }

    /// The one step that must be here. Rendering at `exportSize` directly, with
    /// no scale derived from the on-screen canvas, is why the output size is a
    /// constant rather than something that has to be checked afterwards.
    @MainActor
    static func rasterize(document: EditorDocument, photo: CGImage) throws -> CGImage {
        let size = StoryCanvas.exportSize
        let renderer = ImageRenderer(
            content: DocumentCanvasView(document: document, photo: photo, size: size)
        )
        renderer.proposedSize = ProposedViewSize(size)
        guard let rendered = renderer.cgImage else { throw AppError.exportFailed }
        return rendered
    }

    @concurrent
    static func encode(_ image: CGImage) async throws -> Data {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw AppError.exportFailed
        }
        let options = [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary
        CGImageDestinationAddImage(dest, image, options)
        guard CGImageDestinationFinalize(dest) else { throw AppError.exportFailed }
        return out as Data
    }
}

/// Shared layer sizing. A layer draws at its base size and its transform is
/// applied on top — on the canvas and in the export alike, through the same
/// modifier, so there is nothing left for the two to disagree about.
enum TextRendering {
    static func baseFontSize(in size: CGSize) -> CGFloat {
        0.08 * min(size.width, size.height)
    }

    static func baseStickerFontSize(in size: CGSize) -> CGFloat {
        0.15 * min(size.width, size.height)
    }
}
