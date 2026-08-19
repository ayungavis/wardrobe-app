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

    public static func render(originals: [String: Data], document: EditorDocument) async throws -> Data {
        var photos: [String: CGImage] = [:]
        for layer in document.layers {
            guard case let .photo(content) = layer.content,
                  let original = originals[content.photoID]
            else {
                continue
            }
            // Each layer's own crop: FR-093 lets a document hold several photos,
            // and framing belongs to the layer that shows it.
            photos[content.photoID] = try await prepare(original: original, crop: content.crop)
        }

        let rendered = try await rasterize(document: document, photos: photos)
        return try await encode(rendered)
    }

    /// `@concurrent` rather than bare `nonisolated`: a nonisolated async
    /// function stays on the caller's actor (SE-0461), and every caller here is
    /// `@MainActor`, so without it this would not move at all.
    @concurrent
    static func prepare(original: Data, crop: CropSpec?) async throws -> CGImage {
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

    @MainActor
    static func rasterize(document: EditorDocument, photos: [String: CGImage]) throws -> CGImage {
        let size = StoryCanvas.exportSize
        let renderer = ImageRenderer(
            content: DocumentCanvasView(document: document, photo: { photos[$0] }, size: size)
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
