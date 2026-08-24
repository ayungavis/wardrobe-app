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

    public static func render(originals: [UUID: Data], document: EditorDocument) async throws -> Data {
        var photos: [UUID: CGImage] = [:]
        for layer in document.layers {
            guard case let .photo(content) = layer.content,
                  let original = originals[content.photoID]
            else {
                continue
            }
            photos[content.photoID] = try await prepare(original: original, crop: content.crop)
        }

        if case let .photo(id, crop) = document.background, let original = originals[id] {
            photos[id] = try await prepare(original: original, crop: crop)
        }

        let rendered = try await rasterize(document: document, photos: photos)
        return try await encode(rendered)
    }

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
    static func rasterize(document: EditorDocument, photos: [UUID: CGImage]) throws -> CGImage {
        let size = StoryCanvas.exportSize
        let renderer = ImageRenderer(
            content: DocumentCanvasView(document: document, photo: { photos[$0] }, size: size)
        )
        renderer.proposedSize = ProposedViewSize(size)
        renderer.isOpaque = true
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
