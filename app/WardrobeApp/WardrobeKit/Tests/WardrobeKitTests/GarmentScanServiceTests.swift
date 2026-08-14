import CoreGraphics
import Foundation
import Testing
@testable import WardrobeKit

@MainActor
struct GarmentScanServiceTests {
    private func makeSUT(
        segmentation: StubGarmentSegmentationService = StubGarmentSegmentationService(),
        thumbnails: InMemoryGarmentThumbnailRepository = InMemoryGarmentThumbnailRepository(),
        repository: InMemoryWardrobeItemRepository = InMemoryWardrobeItemRepository()
    ) -> WardrobeGarmentScanService {
        WardrobeGarmentScanService(
            segmentation: segmentation, thumbnails: thumbnails, repository: repository
        )
    }

    private func makePhoto() throws -> Data {
        try SampleCameraService.makeSampleJPEG(width: 120, height: 200)
    }

    @Test func anUndecodablePhotoYieldsNothing() throws {
        #expect(try makeSUT().scan(photo: Data([0x00, 0x01])).isEmpty)
    }

    @Test func aPhotoWithoutGarmentsYieldsNothing() throws {
        let segmentation = StubGarmentSegmentationService()
        segmentation.segmentation = nil

        #expect(try makeSUT(segmentation: segmentation).scan(photo: makePhoto()).isEmpty)
    }

    @Test func eachGarmentIsFingerprintedAndItsCutoutSaved() throws {
        let thumbnails = InMemoryGarmentThumbnailRepository()
        let sut = makeSUT(thumbnails: thumbnails)

        let garments = try sut.scan(photo: makePhoto())

        #expect(garments.count == 1)
        let garment = try #require(garments.first)
        #expect(garment.fingerprint.itemID == garment.id)
        #expect(garment.fingerprint.version == GarmentFingerprinting.version)
        #expect(garment.fingerprint.colorLab.count == 3)
        // The cut-out really is on disk — the review sheet renders from it.
        #expect(try thumbnails.data(forFile: garment.cutoutFile).isEmpty == false)
    }

    /// The proposal has to survive the extraction: this is the seam the editor
    /// will drive, and a scan without matches would silently break duplicates.
    @Test func aGarmentLikeAStoredOneComesBackAsAProposal() throws {
        let repository = InMemoryWardrobeItemRepository()
        let thumbnails = InMemoryGarmentThumbnailRepository()
        let sut = makeSUT(thumbnails: thumbnails, repository: repository)

        let first = try #require(try sut.scan(photo: makePhoto()).first)
        let item = WardrobeItem(
            id: first.id, category: first.category, cutoutFile: first.cutoutFile,
            createdAt: Date(), updatedAt: Date()
        )
        try repository.insert(item, fingerprint: first.fingerprint, wear: WearRecord(itemID: first.id, wornAt: Date()))

        let second = try #require(try sut.scan(photo: makePhoto()).first)

        #expect(second.matches.first?.itemID == first.id)
        #expect(second.decision == .existing(first.id))
    }
}

/// Returns one fixed garment so the pipeline can be exercised without the model.
final class StubGarmentSegmentationService: GarmentSegmentationService, @unchecked Sendable {
    // @unchecked: only mutated during `init`, then read.
    var segmentation: GarmentSegmentation?

    init() {
        // A 4×4 class map whose top half is class 3 ("top").
        let classMap = [[3, 3, 3, 3], [3, 3, 3, 3], [0, 0, 0, 0], [0, 0, 0, 0]]
        let context = CGContext(
            data: nil, width: 40, height: 40, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        context?.setFillColor(CGColor(red: 0.8, green: 0.7, blue: 0.5, alpha: 1))
        context?.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
        if let image = context?.makeImage() {
            segmentation = GarmentSegmentation(classMap: classMap, image: image)
        }
    }

    func segment(_: CGImage) throws -> GarmentSegmentation? {
        segmentation
    }
}
