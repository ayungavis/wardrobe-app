import CoreFoundation
import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

@MainActor
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
    public static func render(original: Data, document: EditorDocument) throws -> Data {
        // Orientation-corrected, metadata-free decode.
        guard var image = ImageDecoding.downsampledImage(from: original, maxPixel: maxOutputPixel) else {
            throw AppError.exportFailed
        }

        if let crop = document.photoCrop {
            let rect = CGRect(
                x: crop.rect.origin.x * CGFloat(image.width),
                y: crop.rect.origin.y * CGFloat(image.height),
                width: crop.rect.width * CGFloat(image.width),
                height: crop.rect.height * CGFloat(image.height)
            ).integral
            guard let cropped = image.cropping(to: rect) else { throw AppError.exportFailed }
            image = cropped
        }

        let size = StoryCanvas.exportSize
        let renderer = ImageRenderer(
            content: DocumentCanvasView(document: document, photo: image, size: size)
        )
        renderer.proposedSize = ProposedViewSize(size)
        guard let rendered = renderer.cgImage else { throw AppError.exportFailed }
        return try encodeJPEG(rendered)
    }

    static func encodeJPEG(_ image: CGImage) throws -> Data {
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
