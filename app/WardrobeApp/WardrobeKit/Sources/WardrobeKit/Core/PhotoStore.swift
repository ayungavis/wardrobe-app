import Foundation

/// Storage for original captures. Originals are write-once (PRD §18.5) —
/// there is deliberately no update API.
public protocol PhotoStore: Sendable {
    @discardableResult
    func saveOriginal(_ data: Data) throws -> String
    func loadOriginal(id: String) throws -> Data
    func deleteOriginal(id: String) throws
}

public final class FilePhotoStore: PhotoStore, @unchecked Sendable {
    // @unchecked: FileManager is thread-safe for these operations.
    private let directory: URL

    public init(directory: URL? = nil) {
        self.directory = directory
            ?? URL.applicationSupportDirectory.appending(path: "Photos")
    }

    public func saveOriginal(_ data: Data) throws -> String {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let id = UUID().uuidString
        var options: Data.WritingOptions = [.atomic]
        #if os(iOS)
            options.insert(.completeFileProtection) // §18.4; full encryption story arrives with the backend
        #endif
        try data.write(to: fileURL(id), options: options)
        return id
    }

    public func loadOriginal(id: String) throws -> Data {
        try Data(contentsOf: fileURL(validated: id))
    }

    public func deleteOriginal(id: String) throws {
        try FileManager.default.removeItem(at: fileURL(validated: id))
    }

    private func fileURL(_ id: String) -> URL {
        directory.appending(path: "\(id).jpg")
    }

    private func fileURL(validated id: String) throws -> URL {
        guard UUID(uuidString: id) != nil else { throw AppError.unexpected }
        return fileURL(id)
    }
}
