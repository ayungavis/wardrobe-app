import CoreGraphics
import Foundation
import Testing
@testable import WardrobeKit

struct GarmentNormalizationTests {
    // MARK: Mask repair

    /// `pattern` uses "#" for garment and "." for background.
    private func makeMask(_ pattern: [String]) -> GarmentMask.Mask {
        let height = pattern.count
        let width = pattern[0].count
        var pixels = [UInt8](repeating: 0, count: width * height)
        for (row, line) in pattern.enumerated() {
            for (column, character) in line.enumerated() where character == "#" {
                pixels[row * width + column] = 255
            }
        }
        return GarmentMask.Mask(
            pixels: pixels,
            width: width,
            height: height,
            bounds: GarmentMask.Bounds(minX: 0, maxX: width - 1, minY: 0, maxY: height - 1)
        )
    }

    @Test func detachedSleeveSurvivesButSpecksAreDropped() throws {
        // Big blob on the left, a sleeve-sized blob on the right, one speck.
        let mask = makeMask([
            "####..##..",
            "####..##..",
            "####..##..",
            "####......",
            "........#.",
        ])

        let repaired = try #require(GarmentMask.repair(mask))

        // The sleeve is kept, so the box still reaches column 7.
        #expect(repaired.mask.bounds.maxX == 7)
        // The speck on row 4 is gone, so the box stops at the body's last row.
        #expect(repaired.mask.bounds.maxY == 3)
        #expect(repaired.quality < 1)
    }

    @Test func holeInsideTheGarmentIsClosedButTheOutsideIsNot() throws {
        let mask = makeMask([
            "......",
            ".####.",
            ".#..#.",
            ".####.",
            "......",
        ])

        let repaired = try #require(GarmentMask.repair(mask))

        #expect(repaired.mask.pixels[2 * 6 + 2] == 255) // hole closed
        #expect(repaired.mask.pixels[2 * 6 + 3] == 255)
        #expect(repaired.holes.filter { $0 == 255 }.count == 2)
        #expect(repaired.mask.pixels[0] == 0) // outside untouched
    }

    @Test func cleanMaskScoresPerfectQuality() throws {
        let mask = makeMask([
            "####",
            "####",
            "####",
        ])

        #expect(try #require(GarmentMask.repair(mask)).quality == 1)
    }

    @Test func emptyMaskRepairsToNil() {
        #expect(GarmentMask.repair(makeMask(["..", ".."])) == nil)
    }

    // MARK: Framing

    private func makeImage(width: Int, height: Int) throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try #require(context.makeImage())
    }

    /// Whatever the garment's size in the photo, the stored cut-out must be the
    /// same canvas at the same fill ratio — that is what makes the grid look
    /// designed and keeps fingerprints comparable.
    @Test(arguments: [(40, 60), (2000, 1200), (100, 100)])
    func everyCutoutLandsOnTheSameCanvas(size: (width: Int, height: Int)) throws {
        let normalized = try #require(
            GarmentNormalization.normalize(makeImage(width: size.width, height: size.height))
        )

        #expect(normalized.width == GarmentNormalization.canvasSize)
        #expect(normalized.height == GarmentNormalization.canvasSize)
    }

    @Test func longestSideFillsTheConfiguredShareOfTheCanvas() throws {
        let normalized = try #require(GarmentNormalization.normalize(makeImage(width: 200, height: 100)))
        let expected = CGFloat(GarmentNormalization.canvasSize) * GarmentNormalization.fillRatio

        let opaque = try opaqueBounds(of: normalized)
        #expect(abs(opaque.width - expected) <= 2)
        // Centred: the margins on both sides match.
        #expect(abs(opaque.minX - (CGFloat(normalized.width) - opaque.width) / 2) <= 2)
    }

    private func opaqueBounds(of image: CGImage) throws -> CGRect {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try #require(CGContext(
            data: &pixels, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))

        var minX = image.width, maxX = 0, minY = image.height, maxY = 0
        for row in 0 ..< image.height {
            for column in 0 ..< image.width where pixels[(row * image.width + column) * 4 + 3] > 0 {
                minX = min(minX, column); maxX = max(maxX, column)
                minY = min(minY, row); maxY = max(maxY, row)
            }
        }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}
