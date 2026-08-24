import Foundation

public protocol PhotoRepository: Sendable {
    @discardableResult
    func saveOriginal(_ data: Data) throws -> UUID
    func loadOriginal(id: UUID) throws -> Data
    func deleteOriginal(id: UUID) throws
}

public extension PhotoRepository {
    func deleteOriginals(of document: EditorDocument, and photoID: UUID?) {
        delete(Set(document.photoIDs).union([photoID].compactMap(\.self)))
    }

    func deleteUnusedOriginals(of document: EditorDocument, imported: [UUID]) {
        delete(Set(imported).subtracting(document.photoIDs))
    }

    private func delete(_ ids: Set<UUID>) {
        for id in ids {
            do {
                try deleteOriginal(id: id)
            } catch {
                Log.report(error)
            }
        }
    }
}

public final class FilePhotoRepository: PhotoRepository, @unchecked Sendable {
    private let directory: URL

    public init(directory: URL? = nil) {
        self.directory = directory
            ?? URL.applicationSupportDirectory.appending(path: "Photos")
    }

    public func saveOriginal(_ data: Data) throws -> UUID {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let id = UUID.v7()
        var options: Data.WritingOptions = [.atomic]
        #if os(iOS)
            options.insert(.completeFileProtection)
        #endif
        try data.write(to: fileURL(id), options: options)
        return id
    }

    public func loadOriginal(id: UUID) throws -> Data {
        try Data(contentsOf: fileURL(id))
    }

    public func deleteOriginal(id: UUID) throws {
        try FileManager.default.removeItem(at: fileURL(id))
    }

    private func fileURL(_ id: UUID) -> URL {
        directory.appending(path: "\(id.uuidString).jpg")
    }
}
