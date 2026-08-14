import CoreGraphics
import Foundation

/// Puts every cut-out on the same canvas at the same scale.
///
/// Raw cut-outs arrive at whatever size the garment happened to occupy in the
/// photo, which makes the wardrobe grid look random and makes fingerprints of
/// the same shirt disagree from one day to the next.
enum GarmentNormalization {
    static let canvasSize = 1024
    /// Share of the canvas the garment's longest side fills. The remainder is
    /// the margin that makes the grid read as a catalogue.
    static let fillRatio: CGFloat = 0.8

    /// Background stays transparent: the grid draws it over `AppColor.surface`,
    /// and fingerprinting flattens it onto a constant grey of its own.
    static func normalize(_ image: CGImage) -> CGImage? {
        let side = CGFloat(canvasSize)
        guard image.width > 0, image.height > 0 else { return nil }

        guard let context = CGContext(
            data: nil,
            width: canvasSize,
            height: canvasSize,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        let scale = side * fillRatio / CGFloat(max(image.width, image.height))
        let width = CGFloat(image.width) * scale
        let height = CGFloat(image.height) * scale
        context.interpolationQuality = .high
        context.draw(
            image,
            in: CGRect(x: (side - width) / 2, y: (side - height) / 2, width: width, height: height)
        )
        return context.makeImage()
    }

    private static func CGColorSpaceDeviceRGB() -> CGColorSpace {
        CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    }
}
