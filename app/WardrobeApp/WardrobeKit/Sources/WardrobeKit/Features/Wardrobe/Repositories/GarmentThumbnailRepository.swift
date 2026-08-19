import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Stores garment cut-outs on disk. PNG because the cut-outs carry alpha.
///
/// The API deals in **file names, never paths**: an iOS container's UUID changes
/// on every reinstall, so a persisted absolute path points at a directory that
/// no longer exists. The directory is resolved fresh on every call instead.
public protocol GarmentThumbnailRepository: Sendable {
    @discardableResult
    func save(_ image: CGImage, id: UUID) throws -> String
    func data(forFile file: String) throws -> Data
    func delete(file: String) throws
    func deleteAll() throws
}

public final class FileGarmentThumbnailRepository: GarmentThumbnailRepository, @unchecked Sendable {
    // @unchecked: FileManager is thread-safe for these operations.
    private let directory: URL

    public init(directory: URL? = nil) {
        self.directory = directory
            ?? URL.applicationSupportDirectory.appending(path: "GarmentThumbnails")
    }

    @discardableResult
    public func save(_ image: CGImage, id: UUID) throws -> String {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = "\(id.uuidString).png"

        guard let destination = CGImageDestinationCreateWithURL(
            directory.appending(path: file) as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else { throw AppError.unexpected }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw AppError.unexpected }

        return file
    }

    public func data(forFile file: String) throws -> Data {
        try Data(contentsOf: directory.appending(path: URL(filePath: file).lastPathComponent))
    }

    public func delete(file: String) throws {
        let url = directory.appending(path: URL(filePath: file).lastPathComponent)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    public func deleteAll() throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.removeItem(at: directory)
    }
}
