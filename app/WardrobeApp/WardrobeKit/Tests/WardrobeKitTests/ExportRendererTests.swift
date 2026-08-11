import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import WardrobeKit

@MainActor
struct ExportRendererTests {
    /// A JPEG deliberately stuffed with EXIF + GPS metadata.
    private func makeJPEGWithMetadata(width: Int = 100, height: Int = 200) throws -> Data {
        let base = try SampleCameraService.makeSampleJPEG(width: width, height: height)
        guard let source = CGImageSourceCreateWithData(base as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw AppError.unexpected
        }

        let metadata: [CFString: Any] = [
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifLensModel: "Test Lens",
                kCGImagePropertyExifDateTimeOriginal: "2026:08:10 10:00:00",
            ],
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: -6.2,
                kCGImagePropertyGPSLongitude: 106.8,
            ],
        ]

        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw AppError.unexpected
        }
        CGImageDestinationAddImage(dest, image, metadata as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw AppError.unexpected }
        return out as Data
    }

    private func properties(of data: Data) throws -> [CFString: Any] {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else {
            throw AppError.unexpected
        }
        return props
    }

    @Test func exportStripsEXIFAndGPS() throws {
        let original = try makeJPEGWithMetadata()

        // Sanity: source really contains the metadata we planted.
        let sourceProps = try properties(of: original)
        #expect(sourceProps[kCGImagePropertyGPSDictionary] != nil)

        let exported = try ExportRenderer.render(original: original, draft: EditDraft())
        let props = try properties(of: exported)

        #expect(props[kCGImagePropertyGPSDictionary] == nil)
        if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            #expect(exif[kCGImagePropertyExifLensModel] == nil)
            #expect(exif[kCGImagePropertyExifDateTimeOriginal] == nil)
        }
    }

    @Test func exportAppliesCropPixelSize() throws {
        let original = try SampleCameraService.makeSampleJPEG(width: 100, height: 200)
        let draft = EditDraft(crop: CropSpec(rect: CGRect(x: 0, y: 0, width: 0.5, height: 0.5)))

        let exported = try ExportRenderer.render(original: original, draft: draft)
        let props = try properties(of: exported)

        #expect(props[kCGImagePropertyPixelWidth] as? Int == 50)
        #expect(props[kCGImagePropertyPixelHeight] as? Int == 100)
    }

    @Test func exportWithStyledTextAndStickersProducesDecodableJPEG() throws {
        let original = try SampleCameraService.makeSampleJPEG(width: 200, height: 200)
        let draft = EditDraft(
            texts: [TextItem(
                content: "OOTD",
                rotationDegrees: -12,
                colorName: TextColor.pink.rawValue,
                hasBackground: true
            )],
            stickers: [StickerItem(
                emoji: "🔥",
                position: CGPoint(x: 0.3, y: 0.7),
                scale: 2,
                rotationDegrees: 30
            )]
        )

        let exported = try ExportRenderer.render(original: original, draft: draft)
        let props = try properties(of: exported)

        #expect((props[kCGImagePropertyPixelWidth] as? Int ?? 0) > 0)
        #expect(props[kCGImagePropertyGPSDictionary] == nil)
    }
}
