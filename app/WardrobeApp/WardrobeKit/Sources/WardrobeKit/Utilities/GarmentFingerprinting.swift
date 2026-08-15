import CoreGraphics
import Foundation
import Vision

/// Turns a normalized cut-out into the numbers that decide whether the user
/// already owns this garment (docs/wardrobe-generation.md §7).
///
/// Everything here reads the **cut-out**, never a generated illustration: the
/// illustration is stochastic and deliberately erases the detail that tells two
/// beige shirts apart.
enum GarmentFingerprinting {
    /// Bumped whenever the maths changes; only fingerprints of the same version
    /// may be compared.
    static var version: String {
        "v1+vision\(VNGenerateImageFeaturePrintRequest.currentRevision)"
    }

    /// Colour statistics are scale-free, so a 256² sample says the same thing as
    /// the full canvas for a sixteenth of the work.
    private static let sampleSize = 256
    /// Below this the pixel is the mask's blurred edge, not the garment.
    private static let opaqueThreshold: UInt8 = 200
    /// Share of the darkest garment pixels dropped before averaging. A hard
    /// shadow band would otherwise drag a beige shirt toward brown.
    private static let shadowShare = 0.25

    private struct GarmentPixel {
        let luminance: Double
        let red: Double
        let green: Double
        let blue: Double
    }

    // MARK: Colour

    /// Mean CIE Lab of the garment's lit pixels, as `[L, a, b]`. Empty when the
    /// image holds no garment.
    ///
    /// One mean rather than k dominant colours: for a patterned garment the mean
    /// is muddy but **stable**, which is what matching needs — the pattern is the
    /// feature print's job. `[Float]` leaves room to grow into clusters later.
    static func colorSignature(of image: CGImage) -> [Float] {
        guard let pixels = sample(image) else { return [] }

        var garment: [GarmentPixel] = []
        for index in stride(from: 0, to: pixels.count, by: 4) {
            guard pixels[index + 3] > opaqueThreshold else { continue }
            let red = Double(pixels[index]) / 255
            let green = Double(pixels[index + 1]) / 255
            let blue = Double(pixels[index + 2]) / 255
            garment.append(GarmentPixel(
                luminance: 0.2126 * red + 0.7152 * green + 0.0722 * blue,
                red: red, green: green, blue: blue
            ))
        }
        guard !garment.isEmpty else { return [] }

        garment.sort { $0.luminance < $1.luminance }
        let lit = garment.dropFirst(Int(Double(garment.count) * shadowShare))
        let count = Double(lit.count)
        let mean = lit.reduce(into: (red: 0.0, green: 0.0, blue: 0.0)) { total, pixel in
            total.red += pixel.red
            total.green += pixel.green
            total.blue += pixel.blue
        }
        return lab(red: mean.red / count, green: mean.green / count, blue: mean.blue / count)
    }

    /// Alpha's bounding box relative to the canvas — tall trousers and wide tops
    /// separate on this even when their colours agree.
    static func aspectRatio(of image: CGImage) -> Float {
        guard let pixels = sample(image) else { return 0 }

        var minX = sampleSize, maxX = 0, minY = sampleSize, maxY = 0
        for row in 0 ..< sampleSize {
            for column in 0 ..< sampleSize {
                guard pixels[(row * sampleSize + column) * 4 + 3] > opaqueThreshold else { continue }
                minX = min(minX, column)
                maxX = max(maxX, column)
                minY = min(minY, row)
                maxY = max(maxY, row)
            }
        }
        guard maxX >= minX, maxY >= minY else { return 0 }
        return Float(maxX - minX + 1) / Float(maxY - minY + 1)
    }

    // MARK: Feature print

    /// Empty when Vision fails: matching then falls back to colour and shape
    /// rather than losing the garment entirely.
    static func featurePrint(of image: CGImage) -> Data {
        guard let flattened = flattenedOntoGrey(image) else { return Data() }

        let request = VNGenerateImageFeaturePrintRequest()
        do {
            try VNImageRequestHandler(cgImage: flattened, options: [:]).perform([request])
        } catch {
            Log.report(error)
            return Data()
        }
        guard let observation = request.results?.first as? VNFeaturePrintObservation else {
            return Data()
        }
        return observation.data
    }

    /// L2 distance over the stored vectors. `VNFeaturePrintObservation` cannot be
    /// rebuilt from disk, so `computeDistance` is not an option — the floats are
    /// compared directly.
    static func distance(_ lhs: Data, _ rhs: Data) -> Float? {
        let left = floats(lhs)
        let right = floats(rhs)
        guard !left.isEmpty, left.count == right.count else { return nil }

        var sum: Float = 0
        for index in left.indices {
            let delta = left[index] - right[index]
            sum += delta * delta
        }
        return sum.squareRoot()
    }

    private static func floats(_ data: Data) -> [Float] {
        guard data.count % MemoryLayout<Float>.size == 0 else { return [] }
        return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }

    // MARK: Pixels

    /// Vision treats transparent regions inconsistently, so the cut-out is
    /// flattened onto a constant grey first — without this the same garment
    /// scores differently just because its hole changed shape.
    private static func flattenedOntoGrey(_ image: CGImage) -> CGImage? {
        guard let context = CGContext(
            data: nil, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }

        context.setFillColor(CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }

    private static func sample(_ image: CGImage) -> [UInt8]? {
        var pixels = [UInt8](repeating: 0, count: sampleSize * sampleSize * 4)
        guard let context = CGContext(
            data: &pixels, width: sampleSize, height: sampleSize,
            bitsPerComponent: 8, bytesPerRow: sampleSize * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.draw(image, in: CGRect(x: 0, y: 0, width: sampleSize, height: sampleSize))
        return pixels
    }

    // MARK: Colour space

    private static func lab(red: Double, green: Double, blue: Double) -> [Float] {
        let linear = [red, green, blue].map { channel -> Double in
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        // sRGB → XYZ (D65), then XYZ → Lab against the D65 white point.
        let xyzX = (0.4124 * linear[0] + 0.3576 * linear[1] + 0.1805 * linear[2]) / 0.95047
        let xyzY = 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
        let xyzZ = (0.0193 * linear[0] + 0.1192 * linear[1] + 0.9505 * linear[2]) / 1.08883

        let fx = pivot(xyzX), fy = pivot(xyzY), fz = pivot(xyzZ)
        return [
            Float(116 * fy - 16),
            Float(500 * (fx - fy)),
            Float(200 * (fy - fz)),
        ]
    }

    private static func pivot(_ value: Double) -> Double {
        value > 0.008856 ? pow(value, 1.0 / 3) : (7.787 * value) + 16.0 / 116
    }
}
