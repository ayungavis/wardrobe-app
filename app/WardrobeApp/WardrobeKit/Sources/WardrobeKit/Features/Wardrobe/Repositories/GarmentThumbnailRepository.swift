import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Stores garment cut-outs on disk. PNG because the cut-outs carry alpha.
public protocol GarmentThumbnailRepository: Sendable {
    @discardableResult
    func save(_ image: CGImage, id: UUID) throws -> String
    func load(path: String) throws -> Data
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
        let url = directory.appending(path: "\(id.uuidString).png")

        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else { throw AppError.unexpected }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw AppError.unexpected }

        return url.path
    }

    public func load(path: String) throws -> Data {
        try Data(contentsOf: URL(filePath: path))
    }
}
