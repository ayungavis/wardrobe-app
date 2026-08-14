import CoreML
import Foundation
import Testing
@testable import WardrobeKit

@MainActor
struct GarmentSegmentationTests {
    // MARK: argmax

    /// Builds a `[1, classes, height, width]` tensor from per-class planes.
    private func makeLogits(planes: [[Float32]], height: Int, width: Int) throws -> MLMultiArray {
        let array = try MLMultiArray(
            shape: [1, NSNumber(value: planes.count), NSNumber(value: height), NSNumber(value: width)],
            dataType: .float32
        )
        let pointer = array.dataPointer.bindMemory(to: Float32.self, capacity: array.count)
        var index = 0
        for plane in planes {
            for value in plane {
                pointer[index] = value
                index += 1
            }
        }
        return array
    }

    @Test func argmaxPicksHighestScoringClassPerPixel() throws {
        // 2×2 image, 2 classes. Class 1 wins on the diagonal.
        let logits = try makeLogits(
            planes: [[9, 0, 0, 9], [0, 9, 9, 0]],
            height: 2, width: 2
        )

        #expect(GarmentMask.argmax(logits: logits) == [[0, 1], [1, 0]])
    }

    @Test func argmaxRejectsUnexpectedShape() throws {
        let array = try MLMultiArray(shape: [2, 2], dataType: .float32)

        #expect(GarmentMask.argmax(logits: array).isEmpty)
    }

    // MARK: mask building

    @Test func buildProducesOneMaskPerPresentCategoryWithBounds() {
        // 3 = top (row 0), 6 = bottom (row 2), 0 = background.
        let classMap = [
            [3, 3, 0],
            [0, 0, 0],
            [0, 6, 6],
        ]

        let masks = GarmentMask.build(from: classMap)

        #expect(Set(masks.keys) == [.top, .bottom])
        #expect(masks[.top]?.bounds == GarmentMask.Bounds(minX: 0, maxX: 1, minY: 0, maxY: 0))
        #expect(masks[.bottom]?.bounds == GarmentMask.Bounds(minX: 1, maxX: 2, minY: 2, maxY: 2))
        #expect(masks[.top]?.pixels.filter { $0 == 255 }.count == 2)
    }

    @Test func buildIgnoresUnmappedClassesAndEmptyInput() {
        #expect(GarmentMask.build(from: [[1, 2], [4, 5]]).isEmpty)
        #expect(GarmentMask.build(from: []).isEmpty)
        #expect(GarmentMask.build(from: [[]]).isEmpty)
    }

    // MARK: thumbnails

    @Test func thumbnailRoundTripsThroughDisk() throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileGarmentThumbnailRepository(directory: directory)
        let image = try ImageDecoding.downsampledImage(
            from: SampleCameraService.makeSampleJPEG(width: 40, height: 60),
            maxPixel: 60
        )
        let cutout = try #require(image)

        let path = try repository.save(cutout, id: UUID())

        #expect(FileManager.default.fileExists(atPath: path))
        #expect(try repository.load(path: path).isEmpty == false)
    }

    #if !os(iOS)
        @Test func hostSegmentationIsANoOp() throws {
            let image = try #require(ImageDecoding.downsampledImage(
                from: SampleCameraService.makeSampleJPEG(width: 20, height: 20),
                maxPixel: 20
            ))

            #expect(try NoopGarmentSegmentationService().segment(image) == nil)
        }
    #endif
}
