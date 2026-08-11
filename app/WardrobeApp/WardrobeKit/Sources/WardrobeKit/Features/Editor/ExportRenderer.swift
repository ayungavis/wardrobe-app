import CoreFoundation
import CoreGraphics
import CoreTransferable
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Sanitized flattened derivative (FR-032): the bytes shared and saved are
/// identical, produced once from pixels only — no source metadata survives.
public struct ExportedPhoto: Equatable, Sendable, Transferable {
    public let data: Data

    public init(data: Data) {
        self.data = data
    }

    public static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .jpeg) { photo in photo.data }
    }
}

@MainActor
public enum ExportRenderer {
    // ponytail: export capped at 4096px long edge — plenty for sharing;
    // raise when a print/quality requirement appears.
    static let maxOutputPixel: CGFloat = 4096

    /// Decodes to pixels (drops all source metadata), applies the crop,
    /// overlays text via the same layout math the editor preview uses, and
    /// re-encodes through `CGImageDestination` writing zero source properties.
    public static func render(original: Data, draft: EditDraft) throws -> Data {
        // Orientation-corrected, metadata-free decode.
        guard var image = ImageDecoding.downsampledImage(from: original, maxPixel: maxOutputPixel) else {
            throw AppError.exportFailed
        }

        if let crop = draft.crop {
            let rect = CGRect(
                x: crop.rect.origin.x * CGFloat(image.width),
                y: crop.rect.origin.y * CGFloat(image.height),
                width: crop.rect.width * CGFloat(image.width),
                height: crop.rect.height * CGFloat(image.height)
            ).integral
            guard let cropped = image.cropping(to: rect) else { throw AppError.exportFailed }
            image = cropped
        }

        if draft.texts.isEmpty, draft.stickers.isEmpty {
            return try encodeJPEG(image) // no compositing needed
        }

        let size = CGSize(width: image.width, height: image.height)
        let renderer = ImageRenderer(
            content: ExportCompositionView(image: image, texts: draft.texts, stickers: draft.stickers, size: size)
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

/// Shared text layout math so the editor preview and the export stay WYSIWYG.
enum TextRendering {
    static func fontSize(for item: TextItem, in size: CGSize) -> CGFloat {
        0.08 * min(size.width, size.height) * item.scale
    }

    static func stickerFontSize(for item: StickerItem, in size: CGSize) -> CGFloat {
        0.15 * min(size.width, size.height) * item.scale
    }
}

/// Static composition rendered for export — uses the same label components
/// as the editor canvas, so output matches the preview.
struct ExportCompositionView: View {
    let image: CGImage
    let texts: [TextItem]
    let stickers: [StickerItem]
    let size: CGSize

    var body: some View {
        ZStack {
            Image(decorative: image, scale: 1)
                .resizable()

            ForEach(stickers) { item in
                StickerLabel(item: item, fontSize: TextRendering.stickerFontSize(for: item, in: size))
                    .position(x: item.position.x * size.width, y: item.position.y * size.height)
            }

            ForEach(texts) { item in
                TextItemLabel(item: item, fontSize: TextRendering.fontSize(for: item, in: size))
                    .position(x: item.position.x * size.width, y: item.position.y * size.height)
            }
        }
        .frame(width: size.width, height: size.height)
    }
}
