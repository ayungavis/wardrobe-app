import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import WardrobeKit

@MainActor
struct CanvasCentringTests {
    private func solidJPEG(width: Int, height: Int, red: CGFloat, green: CGFloat, blue: CGFloat) throws -> Data {
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            throw AppError.unexpected
        }
        context.setFillColor(CGColor(srgbRed: red, green: green, blue: blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        guard let image = context.makeImage() else { throw AppError.unexpected }
        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            out, UTType.jpeg.identifier as CFString, 1, nil
        ) else {
            throw AppError.unexpected
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw AppError.unexpected }
        return out as Data
    }

    private func redCentroidFraction(of exported: Data) throws -> CGFloat {
        let decoded = try #require(ImageDecoding.downsampledImage(from: exported, maxPixel: 400))
        let width = decoded.width
        let height = decoded.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        try pixels.withUnsafeMutableBytes { raw in
            guard let context = CGContext(
                data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                throw AppError.unexpected
            }
            context.draw(decoded, in: CGRect(x: 0, y: 0, width: width, height: height))
        }

        var weighted = 0.0
        var count = 0.0
        for y in 0 ..< height {
            for x in 0 ..< width {
                let offset = (y * width + x) * 4
                let red = Int(pixels[offset])
                let green = Int(pixels[offset + 1])
                let blue = Int(pixels[offset + 2])
                guard red > 140, red > green + 60, red > blue + 60 else { continue }
                weighted += Double(x)
                count += 1
            }
        }
        try #require(count > 0, "no red pixels reached the export, so there is nothing to centre")
        return CGFloat(weighted / count) / CGFloat(width)
    }

    private func makeDocument() -> EditorDocument {
        EditorDocument.fixture(photoID: id("photo-1"))
    }

    @Test func aPhotoBackgroundDoesNotShiftTheComposition() async throws {
        let layer = try solidJPEG(width: 400, height: 400, red: 1, green: 0, blue: 0)
        let background = try solidJPEG(width: 800, height: 400, red: 0, green: 0, blue: 1)
        var document = makeDocument()
        document.background = .photo(id: id("bg-1"), crop: nil)

        let exported = try await ExportService.render(
            originals: [id("photo-1"): layer, id("bg-1"): background], document: document
        )

        let centre = try redCentroidFraction(of: exported)
        #expect(
            abs(centre - 0.5) < 0.03,
            "a background wider than the canvas grows the stack the layers are positioned inside"
        )
    }

    @Test func aPaletteBackgroundKeepsTheSameComposition() async throws {
        let layer = try solidJPEG(width: 400, height: 400, red: 1, green: 0, blue: 0)
        var document = makeDocument()
        document.background = .palette(.white)

        let exported = try await ExportService.render(
            originals: [id("photo-1"): layer], document: document
        )

        let centre = try redCentroidFraction(of: exported)
        #expect(abs(centre - 0.5) < 0.03, "the palette case is the one that already works")
    }
}
