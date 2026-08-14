//
//  GarmentSegmentationService.swift
//  WardrobeKit
//
//  Created by Luisa Haning Tyas on 12/08/26.
//

import Vision
import CoreML
import CoreImage
import UIKit

final class GarmentSegmentationService: @unchecked Sendable {

    enum GarmentCategory: CaseIterable {
        case top, bottom

        var classIDs: [Int] {
            switch self {
            case .top: return [3]   // "top"
            case .bottom: return [6]          // "pants"
            
            }
        }
    }

    func segment(_ uiImage: UIImage) throws -> (classMap: [[Int]], uprightImage: CGImage)? {
        guard let cgImage = uiImage.cgImage else { return nil }
        let orientation = CGImagePropertyOrientation(uiImage.imageOrientation)

        let ciImage = CIImage(cgImage: cgImage).oriented(orientation)
        let context = CIContext()
        guard let uprightCGImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }

        guard let inputBuffer = Self.pixelBuffer(from: uprightCGImage, width: 384, height: 576) else { return nil }
        
        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndGPU
        
        let model = try FASHNSegFormer(configuration: config) // ⚠️ your actual class name
        let prediction = try model.prediction(image: inputBuffer)

        let logits = prediction.logits // shape: 1 x 18 x 576 x 384
        print("Logits shape: \(logits.shape)")
        let classMap = Self.argmax(logits: logits)

        return (classMap, uprightCGImage)
    }
    
    private static func argmax(logits: MLMultiArray) -> [[Int]] {
        
        let shape = logits.shape.map { $0.intValue }
            print("Logits shape: \(shape)")

            guard shape.count == 4 else {
                print("❌ Unexpected shape, aborting")
                return []
            }

        let numClasses = shape[1]
            let height = shape[2]
            let width = shape[3]
            let totalExpected = numClasses * height * width

            guard logits.count == totalExpected else {
                print("❌ Shape mismatch: expected \(totalExpected) values but array has \(logits.count)")
                return []
            }

        let pointer = logits.dataPointer.bindMemory(to: Float32.self, capacity: totalExpected)

        var classMap = [[Int]](repeating: [Int](repeating: 0, count: width), count: height)

        for y in 0..<height {
            for x in 0..<width {
                var bestClass = 0
                var bestScore: Float32 = -Float32.greatestFiniteMagnitude

                for c in 0..<numClasses {
                    // Index math for [1, numClasses, height, width] layout
                    let index = c * (height * width) + y * width + x
                    let score = pointer[index]
                    if score > bestScore {
                        bestScore = score
                        bestClass = c
                    }
                }
                classMap[y][x] = bestClass
            }
        }
        return classMap
    }
    
    /// Computes cutouts for ALL categories in one fast pass over the pixels, instead of scanning once per category.
    func cutoutAll(classMap: [[Int]], uprightImage: CGImage) -> [GarmentCategory: UIImage] {
        guard !classMap.isEmpty, !classMap[0].isEmpty else {
                print("❌ classMap is empty — argmax likely failed upstream")
                return [:]
            }
        
        let mapHeight = classMap.count
        let mapWidth = classMap[0].count

        var masks: [GarmentCategory: [UInt8]] = [:]
            var bounds: [GarmentCategory: (minX: Int, maxX: Int, minY: Int, maxY: Int)] = [:]
            for category in GarmentCategory.allCases {
                masks[category] = [UInt8](repeating: 0, count: mapWidth * mapHeight)
            }

            var idToCategory: [Int: GarmentCategory] = [:]
            for category in GarmentCategory.allCases {
                for id in category.classIDs { idToCategory[id] = category }
            }

            for y in 0..<mapHeight {
                for x in 0..<mapWidth {
                    let classValue = classMap[y][x]
                    guard let category = idToCategory[classValue] else { continue }

                    masks[category]![y * mapWidth + x] = 255

                    if var b = bounds[category] {
                        b.minX = min(b.minX, x); b.maxX = max(b.maxX, x)
                        b.minY = min(b.minY, y); b.maxY = max(b.maxY, y)
                        bounds[category] = b
                    } else {
                        bounds[category] = (x, x, y, y)
                    }
                }
            }

        var results: [GarmentCategory: UIImage] = [:]
        let photoCI = CIImage(cgImage: uprightImage)
        let ciContext = CIContext()

        for category in GarmentCategory.allCases {
            guard let bound = bounds[category],
                  let maskCGImage = Self.grayscaleCGImage(from: masks[category]!, width: mapWidth, height: mapHeight) else { continue }

            let maskCI = CIImage(cgImage: maskCGImage)
            let scaleX = photoCI.extent.width / maskCI.extent.width
            let scaleY = photoCI.extent.height / maskCI.extent.height
            let scaledMask = maskCI.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

            let softenedMask = scaledMask
                .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 2.0])
                .cropped(to: scaledMask.extent)
            
            let filter = CIFilter(name: "CIBlendWithMask")
            filter?.setValue(photoCI, forKey: kCIInputImageKey)
            filter?.setValue(softenedMask, forKey: kCIInputMaskImageKey)
            guard let cutoutCI = filter?.outputImage,
                  let cutoutCGImage = ciContext.createCGImage(cutoutCI, from: cutoutCI.extent) else { continue }

            let realMinX = CGFloat(bound.minX) * scaleX
            let realMaxX = CGFloat(bound.maxX) * scaleX
            let realMinY = CGFloat(bound.minY) * scaleY
            let realMaxY = CGFloat(bound.maxY) * scaleY
            let cropRect = CGRect(x: realMinX, y: realMinY, width: realMaxX - realMinX, height: realMaxY - realMinY)
                .insetBy(dx: -10, dy: -10)
                .intersection(CGRect(x: 0, y: 0, width: cutoutCGImage.width, height: cutoutCGImage.height))

            if let finalCrop = cutoutCGImage.cropping(to: cropRect) {
                results[category] = UIImage(cgImage: finalCrop)
            } else {
                results[category] = UIImage(cgImage: cutoutCGImage)
            }
        }

        return results
    }

    private static func pixelBuffer(from cgImage: CGImage, width: Int, height: Int) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ]
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32ARGB, attrs as CFDictionary, &pixelBuffer)
        guard let buffer = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else { return nil }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }

    private static func grayscaleCGImage(from bytes: [UInt8], width: Int, height: Int) -> CGImage? {
        var bytes = bytes
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let context = CGContext(
            data: &bytes, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width, space: colorSpace, bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        return context.makeImage()
    }
}
