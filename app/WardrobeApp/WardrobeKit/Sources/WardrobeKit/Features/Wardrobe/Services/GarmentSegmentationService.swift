import CoreGraphics
import CoreImage
import CoreML
import Foundation

/// A per-pixel class map plus the upright photo it was computed from.
public struct GarmentSegmentation: Sendable {
    public let classMap: [[Int]]
    public let image: CGImage

    public init(classMap: [[Int]], image: CGImage) {
        self.classMap = classMap
        self.image = image
    }
}

/// Splits a photo into garment masks. The model only exists on iOS, so the
/// protocol is what the rest of the app depends on — same shape as
/// `PhotoLibraryService` and `PhotoLibrarySaveService`.
public protocol GarmentSegmentationService: Sendable {
    func segment(_ image: CGImage) throws -> GarmentSegmentation?
}

/// A repaired, normalized garment image and how much its mask could be trusted.
public struct GarmentCutout: Sendable {
    public let image: CGImage
    public let maskQuality: Float
}

// MARK: - Cut-outs (pure, cross-platform, unit-testable)

public extension GarmentSegmentationService {
    /// One pass over the class map produces every category's cut-out, instead
    /// of scanning once per category. Each one comes out repaired (§7) and on
    /// the shared 1024² canvas.
    func cutouts(from segmentation: GarmentSegmentation) -> [GarmentCategory: GarmentCutout] {
        let masks = GarmentMask.build(from: segmentation.classMap)
        guard !masks.isEmpty else { return [:] }

        let photo = CIImage(cgImage: segmentation.image)
        let context = CIContext()
        var results: [GarmentCategory: GarmentCutout] = [:]

        for (category, mask) in masks {
            guard let repaired = GarmentMask.repair(mask),
                  let cutout = GarmentMask.cutout(photo: photo, repaired: repaired, context: context),
                  let normalized = GarmentNormalization.normalize(cutout)
            else { continue }
            results[category] = GarmentCutout(image: normalized, maskQuality: repaired.quality)
        }
        return results
    }
}

/// Mask geometry and compositing. Free of UIKit and of the model, so the host
/// build and the tests can exercise all of it.
enum GarmentMask {
    struct Bounds: Equatable {
        var minX: Int
        var maxX: Int
        var minY: Int
        var maxY: Int
    }

    struct Mask {
        let pixels: [UInt8]
        let width: Int
        let height: Int
        let bounds: Bounds
    }

    /// Turns the class map into one binary mask per category, tracking each
    /// one's bounding box in the same pass.
    static func build(from classMap: [[Int]]) -> [GarmentCategory: Mask] {
        guard let firstRow = classMap.first, !firstRow.isEmpty else { return [:] }

        let height = classMap.count
        let width = firstRow.count
        var categoryForClassID: [Int: GarmentCategory] = [:]
        for category in GarmentCategory.allCases {
            for id in category.classIDs {
                categoryForClassID[id] = category
            }
        }

        var pixels: [GarmentCategory: [UInt8]] = [:]
        var bounds: [GarmentCategory: Bounds] = [:]

        for row in 0 ..< height {
            for column in 0 ..< width {
                guard let category = categoryForClassID[classMap[row][column]] else { continue }
                pixels[category, default: [UInt8](repeating: 0, count: width * height)][row * width + column] = 255
                bounds[category] = expand(bounds[category], toInclude: column, row)
            }
        }

        return pixels.reduce(into: [:]) { result, entry in
            guard let box = bounds[entry.key] else { return }
            result[entry.key] = Mask(pixels: entry.value, width: width, height: height, bounds: box)
        }
    }

    private static func expand(_ bounds: Bounds?, toInclude column: Int, _ row: Int) -> Bounds {
        guard var box = bounds else {
            return Bounds(minX: column, maxX: column, minY: row, maxY: row)
        }
        box.minX = min(box.minX, column)
        box.maxX = max(box.maxX, column)
        box.minY = min(box.minY, row)
        box.maxY = max(box.maxY, row)
        return box
    }

    /// Applies the repaired mask to the photo, paints the closed holes with the
    /// garment's own average colour, and crops to the bounding box.
    ///
    /// Holes must not simply show the photo through: what sits behind them is
    /// the wearer's arm, which looks worse than the hole did. Padding is left to
    /// `GarmentNormalization` so framing has a single owner.
    static func cutout(photo: CIImage, repaired: Repaired, context: CIContext) -> CGImage? {
        let mask = repaired.mask
        guard let garmentMask = softenedMask(repaired.holes.isEmpty ? mask.pixels : withoutHoles(repaired),
                                             like: mask, photo: photo),
            let filledMask = softenedMask(mask.pixels, like: mask, photo: photo)
        else { return nil }

        let garment = photo.applyingFilter("CIBlendWithMask", parameters: [kCIInputMaskImageKey: garmentMask])
        let patch = CIImage(color: averageColor(of: garment, context: context))
            .cropped(to: photo.extent)
            .applyingFilter("CIBlendWithMask", parameters: [kCIInputMaskImageKey: filledMask])
        let composed = garment.composited(over: patch)

        guard let image = context.createCGImage(composed, from: composed.extent) else { return nil }
        let box = mask.bounds
        let scaleX = photo.extent.width / CGFloat(mask.width)
        let scaleY = photo.extent.height / CGFloat(mask.height)
        let cropRect = CGRect(
            x: CGFloat(box.minX) * scaleX,
            y: CGFloat(box.minY) * scaleY,
            width: CGFloat(box.maxX - box.minX + 1) * scaleX,
            height: CGFloat(box.maxY - box.minY + 1) * scaleY
        ).intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))

        return image.cropping(to: cropRect) ?? image
    }

    private static func withoutHoles(_ repaired: Repaired) -> [UInt8] {
        var pixels = repaired.mask.pixels
        for index in pixels.indices where repaired.holes[index] == 255 {
            pixels[index] = 0
        }
        return pixels
    }

    private static func softenedMask(_ pixels: [UInt8], like mask: Mask, photo: CIImage) -> CIImage? {
        let source = Mask(pixels: pixels, width: mask.width, height: mask.height, bounds: mask.bounds)
        guard let image = grayscaleImage(from: source) else { return nil }

        let maskCI = CIImage(cgImage: image)
        let scaled = maskCI.transformed(by: CGAffineTransform(
            scaleX: photo.extent.width / maskCI.extent.width,
            y: photo.extent.height / maskCI.extent.height
        ))
        return scaled
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 2.0])
            .cropped(to: scaled.extent)
    }

    // ponytail: average rather than median — one GPU call instead of a
    // histogram pass, and the difference is invisible in a flat fill.

    /// `CIAreaAverage` includes the transparent pixels, so the premultiplied
    /// result is divided by the alpha average to recover the garment's colour.
    private static func averageColor(of image: CIImage, context: CIContext) -> CIColor {
        let average = image.applyingFilter(
            "CIAreaAverage",
            parameters: [kCIInputExtentKey: CIVector(cgRect: image.extent)]
        )
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(
            average,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
        )

        let alpha = CGFloat(pixel[3]) / 255
        guard alpha > 0.01 else { return CIColor(red: 0.5, green: 0.5, blue: 0.5) }
        return CIColor(
            red: CGFloat(pixel[0]) / 255 / alpha,
            green: CGFloat(pixel[1]) / 255 / alpha,
            blue: CGFloat(pixel[2]) / 255 / alpha
        )
    }

    private static func grayscaleImage(from mask: Mask) -> CGImage? {
        var pixels = mask.pixels
        guard let context = CGContext(
            data: &pixels,
            width: mask.width,
            height: mask.height,
            bitsPerComponent: 8,
            bytesPerRow: mask.width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        return context.makeImage()
    }

    /// Highest-scoring class per pixel from a `[1, classes, height, width]` tensor.
    static func argmax(logits: MLMultiArray) -> [[Int]] {
        let shape = logits.shape.map(\.intValue)
        guard shape.count == 4 else { return [] }

        let classCount = shape[1]
        let height = shape[2]
        let width = shape[3]
        guard logits.count == classCount * height * width else { return [] }

        let scores = logits.dataPointer.bindMemory(to: Float32.self, capacity: logits.count)
        var classMap = [[Int]](repeating: [Int](repeating: 0, count: width), count: height)

        for row in 0 ..< height {
            for column in 0 ..< width {
                var bestClass = 0
                var bestScore = -Float32.greatestFiniteMagnitude
                for classIndex in 0 ..< classCount {
                    let score = scores[classIndex * (height * width) + row * width + column]
                    if score > bestScore {
                        bestScore = score
                        bestClass = classIndex
                    }
                }
                classMap[row][column] = bestClass
            }
        }
        return classMap
    }

    static func pixelBuffer(from image: CGImage, width: Int, height: Int) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        ]
        CVPixelBufferCreate(
            kCFAllocatorDefault, width, height,
            kCVPixelFormatType_32ARGB, attributes as CFDictionary, &buffer
        )
        guard let buffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else { return nil }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }
}

// MARK: - Implementations

#if os(iOS)
    /// The FASHN SegFormer model. Its Swift class is generated by Xcode's
    /// `CoreMLModelCodegen`, which SwiftPM does not run — hence the platform gate.
    public struct FASHNGarmentSegmentationService: GarmentSegmentationService {
        private static let inputSize = (width: 384, height: 576)

        /// Loaded once for the whole process: the weights are ~128 MB, and the
        /// previous code re-loaded them for every single photo.
        ///
        /// nonisolated(unsafe): the generated wrapper is not `Sendable`, but it
        /// is immutable once loaded and `MLModel` predictions are thread-safe.
        private nonisolated(unsafe) static let model: FASHNSegFormer? = {
            let configuration = MLModelConfiguration()
            configuration.computeUnits = .cpuAndGPU
            do {
                return try FASHNSegFormer(configuration: configuration)
            } catch {
                Log.report(error)
                return nil
            }
        }()

        public init() {}

        public func segment(_ image: CGImage) throws -> GarmentSegmentation? {
            guard let model = Self.model else { throw AppError.unexpected }
            guard let input = GarmentMask.pixelBuffer(
                from: image,
                width: Self.inputSize.width,
                height: Self.inputSize.height
            ) else { return nil }

            let prediction = try model.prediction(image: input)
            let classMap = GarmentMask.argmax(logits: prediction.logits)
            guard !classMap.isEmpty else { return nil }
            return GarmentSegmentation(classMap: classMap, image: image)
        }
    }
#else
    /// macOS host builds and unit tests have no compiled model.
    public struct NoopGarmentSegmentationService: GarmentSegmentationService {
        public init() {}
        public func segment(_: CGImage) throws -> GarmentSegmentation? {
            nil
        }
    }
#endif
