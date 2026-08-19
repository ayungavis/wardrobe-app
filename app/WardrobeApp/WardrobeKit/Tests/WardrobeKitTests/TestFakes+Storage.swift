import CoreGraphics
import Foundation
@testable import WardrobeKit

// The two file-backed repositories, faked in memory. Split out of
// `TestFakes.swift` only because that file reached the length limit.

final class InMemoryCompletionPreviewRepository: CompletionPreviewRepository, @unchecked Sendable {
    var files: [String: Data] = [:]
    private(set) var deleteAllCount = 0
    /// Set to make saving fail, which is how the "✓ still completes when the
    /// render cannot be stored" case is written.
    var saveError: Error?

    func save(_ data: Data, id: UUID) throws -> String {
        if let saveError {
            throw saveError
        }
        let file = "\(id.uuidString).jpg"
        files[file] = data
        return file
    }

    func data(forFile file: String) throws -> Data {
        guard let data = files[URL(filePath: file).lastPathComponent] else { throw AppError.unexpected }
        return data
    }

    func delete(file: String) throws {
        files[URL(filePath: file).lastPathComponent] = nil
    }

    func deleteAll() throws {
        deleteAllCount += 1
        files.removeAll()
    }
}

final class InMemoryGarmentThumbnailRepository: GarmentThumbnailRepository, @unchecked Sendable {
    var files: [String: Data] = [:]
    private(set) var deleteAllCount = 0

    func save(_: CGImage, id: UUID) throws -> String {
        let file = "\(id.uuidString).png"
        files[file] = Data([0x01])
        return file
    }

    func data(forFile file: String) throws -> Data {
        guard let data = files[URL(filePath: file).lastPathComponent] else { throw AppError.unexpected }
        return data
    }

    func delete(file: String) throws {
        files[URL(filePath: file).lastPathComponent] = nil
    }

    func deleteAll() throws {
        deleteAllCount += 1
        files.removeAll()
    }
}
