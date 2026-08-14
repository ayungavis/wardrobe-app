import CoreGraphics
import Foundation
import Testing
@testable import WardrobeKit

@MainActor
struct GarmentThumbnailRepositoryTests {
    private func makeImage() throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        return try #require(context.makeImage())
    }

    private func makeDirectory() -> URL {
        URL.temporaryDirectory.appending(path: UUID().uuidString)
    }

    /// The rule this whole type exists to enforce: an iOS container UUID changes
    /// on every reinstall, so a persisted absolute path is a dangling pointer.
    @Test func saveReturnsABareFileNameNeverAPath() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sut = FileGarmentThumbnailRepository(directory: directory)

        let file = try sut.save(makeImage(), id: UUID())

        #expect(!file.contains("/"))
        #expect(file.hasSuffix(".png"))
        #expect(try sut.data(forFile: file).isEmpty == false)
    }

    /// Rows written before that rule hold a path into a container that no longer
    /// exists; resolving by file name finds the image anyway.
    @Test func legacyAbsolutePathStillResolves() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sut = FileGarmentThumbnailRepository(directory: directory)
        let id = UUID()
        let file = try sut.save(makeImage(), id: id)

        let stale = "/var/mobile/Containers/Data/Application/DEAD-BEEF/Library/Application Support/x/\(file)"

        #expect(try sut.data(forFile: stale) == sut.data(forFile: file))
    }

    @Test func missingFileThrows() {
        let sut = FileGarmentThumbnailRepository(directory: makeDirectory())

        #expect(throws: (any Error).self) { try sut.data(forFile: "nope.png") }
    }

    @Test func deleteAllRemovesEveryThumbnailAndIsSafeWhenEmpty() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sut = FileGarmentThumbnailRepository(directory: directory)
        let file = try sut.save(makeImage(), id: UUID())

        try sut.deleteAll()
        try sut.deleteAll() // nothing left to delete must not throw

        #expect(throws: (any Error).self) { try sut.data(forFile: file) }
    }
}
