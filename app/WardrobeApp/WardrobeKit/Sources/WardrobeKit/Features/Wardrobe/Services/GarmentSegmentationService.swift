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

// MARK: - Cut-outs (pure, cross-platform, unit-testable)

public extension GarmentSegmentationService {
    /// One pass over the class map produces every category's cut-out, instead
    /// of scanning once per category.
    func cutouts(from segmentation: GarmentSegmentation) -> [GarmentCategory: CGImage] {
        let masks = GarmentMask.build(from: segmentation.classMap)
        guard !masks.isEmpty else { return [:] }

        let photo = CIImage(cgImage: segmentation.image)
        let context = CIContext()
        var results: [GarmentCategory: CGImage] = [:]

        for (category, mask) in masks {
            if let cutout = GarmentMask.cutout(photo: photo, mask: mask, context: context) {
                results[category] = cutout
            }
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

    /// Applies the mask to the photo and crops to the garment's bounding box.
    static func cutout(photo: CIImage, mask: Mask, context: CIContext) -> CGImage? {
        guard let maskImage = grayscaleImage(from: mask) else { return nil }

        let maskCI = CIImage(cgImage: maskImage)
        let scaleX = photo.extent.width / maskCI.extent.width
        let scaleY = photo.extent.height / maskCI.extent.height
        let scaled = maskCI.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        let softened = scaled
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 2.0])
            .cropped(to: scaled.extent)

        let blended = photo.applyingFilter(
            "CIBlendWithMask",
            parameters: [kCIInputMaskImageKey: softened]
        )
        guard let composited = context.createCGImage(blended, from: blended.extent) else { return nil }

        let box = mask.bounds
        let cropRect = CGRect(
            x: CGFloat(box.minX) * scaleX,
            y: CGFloat(box.minY) * scaleY,
            width: CGFloat(box.maxX - box.minX) * scaleX,
            height: CGFloat(box.maxY - box.minY) * scaleY
        )
        .insetBy(dx: -10, dy: -10)
        .intersection(CGRect(x: 0, y: 0, width: composited.width, height: composited.height))

        return composited.cropping(to: cropRect) ?? composited
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
