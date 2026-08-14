import CoreGraphics
import Foundation
import Testing
@testable import WardrobeKit

@MainActor
struct GarmentFingerprintingTests {
    /// A garment-shaped patch on a transparent canvas, optionally with the
    /// bottom half darkened to stand in for a hard shadow.
    private func makeCutout(
        red: CGFloat, green: CGFloat, blue: CGFloat,
        size: (width: Int, height: Int) = (200, 200),
        shadowed: Bool = false
    ) throws -> CGImage {
        let canvas = 400
        let context = try #require(CGContext(
            data: nil, width: canvas, height: canvas, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let origin = CGPoint(x: (canvas - size.width) / 2, y: (canvas - size.height) / 2)
        let rect = CGRect(origin: origin, size: CGSize(width: size.width, height: size.height))

        context.setFillColor(CGColor(red: red, green: green, blue: blue, alpha: 1))
        context.fill(rect)
        if shadowed {
            context.setFillColor(CGColor(red: red * 0.35, green: green * 0.35, blue: blue * 0.35, alpha: 1))
            context.fill(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height / 2))
        }
        return try #require(context.makeImage())
    }

    private func labDistance(_ lhs: [Float], _ rhs: [Float]) -> Float {
        zip(lhs, rhs).map { ($0 - $1) * ($0 - $1) }.reduce(0, +).squareRoot()
    }

    // MARK: Colour

    /// The whole point of dropping the darkest quarter: `top.png` has a hard
    /// shadow band, and a naive mean would read it as a different, browner shirt.
    @Test func shadowDoesNotMoveTheColourSignature() throws {
        let plain = try GarmentFingerprinting.colorSignature(of: makeCutout(red: 0.85, green: 0.8, blue: 0.7))
        let shadowed = try GarmentFingerprinting.colorSignature(
            of: makeCutout(red: 0.85, green: 0.8, blue: 0.7, shadowed: true)
        )
        let other = try GarmentFingerprinting.colorSignature(of: makeCutout(red: 0.1, green: 0.1, blue: 0.6))

        #expect(labDistance(plain, shadowed) < labDistance(plain, other))
    }

    @Test func differentColoursAreFarApart() throws {
        let beige = try GarmentFingerprinting.colorSignature(of: makeCutout(red: 0.85, green: 0.8, blue: 0.7))
        let navy = try GarmentFingerprinting.colorSignature(of: makeCutout(red: 0.1, green: 0.1, blue: 0.4))

        #expect(beige.count == 3)
        #expect(labDistance(beige, navy) > 20)
    }

    @Test func transparentImageHasNoSignature() throws {
        let context = try #require(CGContext(
            data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let empty = try #require(context.makeImage())

        #expect(GarmentFingerprinting.colorSignature(of: empty).isEmpty)
        #expect(GarmentFingerprinting.aspectRatio(of: empty) == 0)
    }

    // MARK: Shape

    @Test func aspectRatioFollowsTheGarmentNotTheCanvas() throws {
        let wide = try GarmentFingerprinting.aspectRatio(of: makeCutout(
            red: 0.5, green: 0.5, blue: 0.5, size: (240, 120)
        ))
        let tall = try GarmentFingerprinting.aspectRatio(of: makeCutout(
            red: 0.5, green: 0.5, blue: 0.5, size: (120, 240)
        ))

        #expect(wide > 1.5)
        #expect(tall < 0.7)
    }

    // MARK: Feature print

    @Test func identicalImagesHaveZeroDistance() throws {
        let image = try makeCutout(red: 0.2, green: 0.6, blue: 0.3)
        let print = GarmentFingerprinting.featurePrint(of: image)

        #expect(!print.isEmpty)
        #expect(GarmentFingerprinting.distance(print, print) == 0)
    }

    @Test func differentImagesHaveNonZeroDistance() throws {
        let lhs = try GarmentFingerprinting.featurePrint(of: makeCutout(red: 0.9, green: 0.1, blue: 0.1))
        let rhs = try GarmentFingerprinting.featurePrint(
            of: makeCutout(red: 0.1, green: 0.1, blue: 0.9, size: (300, 90))
        )

        #expect(try #require(GarmentFingerprinting.distance(lhs, rhs)) > 0)
    }

    @Test func distanceRejectsEmptyOrMismatchedVectors() {
        let vector = Data([0, 0, 0, 0, 0, 0, 0, 0])

        #expect(GarmentFingerprinting.distance(Data(), vector) == nil)
        #expect(GarmentFingerprinting.distance(vector, Data([0, 0, 0, 0])) == nil)
    }

    @Test func versionNamesTheVisionRevision() {
        #expect(GarmentFingerprinting.version.hasPrefix("v1+vision"))
        #expect(GarmentFingerprinting.version.count > "v1+vision".count)
    }
}
