import Foundation
import Testing
@testable import WardrobeKit

@MainActor
struct CompletionPreviewRepositoryTests {
    private func makeDirectory() -> URL {
        URL.temporaryDirectory.appending(path: UUID().uuidString)
    }

    /// The rule this whole type exists to enforce: an iOS container UUID changes
    /// on every reinstall, so a persisted absolute path is a dangling pointer.
    @Test func saveReturnsABareFileNameNeverAPath() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sut = FileCompletionPreviewRepository(directory: directory)

        let file = try sut.save(Data([0xFF, 0xD8]), id: UUID())

        #expect(!file.contains("/"))
        #expect(file.hasSuffix(".jpg"))
        #expect(try sut.data(forFile: file) == Data([0xFF, 0xD8]))
    }

    /// A name written before that rule holds a path into a container that no
    /// longer exists; resolving by file name finds the preview anyway.
    @Test func legacyAbsolutePathStillResolves() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sut = FileCompletionPreviewRepository(directory: directory)
        let file = try sut.save(Data([0x01]), id: UUID())

        let stale = "/var/mobile/Containers/Data/Application/DEAD-BEEF/Library/Application Support/x/\(file)"

        #expect(try sut.data(forFile: stale) == sut.data(forFile: file))
    }

    @Test func missingFileThrows() {
        let sut = FileCompletionPreviewRepository(directory: makeDirectory())

        #expect(throws: (any Error).self) { try sut.data(forFile: "nope.jpg") }
    }

    @Test func deleteRemovesOnePreviewAndIsSafeWhenAlreadyGone() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sut = FileCompletionPreviewRepository(directory: directory)
        let file = try sut.save(Data([0x01]), id: UUID())

        try sut.delete(file: file)
        try sut.delete(file: file) // deleting twice must not throw

        #expect(throws: (any Error).self) { try sut.data(forFile: file) }
    }

    @Test func deleteAllRemovesEveryPreviewAndIsSafeWhenEmpty() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sut = FileCompletionPreviewRepository(directory: directory)
        let file = try sut.save(Data([0x01]), id: UUID())

        try sut.deleteAll()
        try sut.deleteAll() // nothing left to delete must not throw

        #expect(throws: (any Error).self) { try sut.data(forFile: file) }
    }
}
