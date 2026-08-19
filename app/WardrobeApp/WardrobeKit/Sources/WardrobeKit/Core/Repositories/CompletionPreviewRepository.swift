import Foundation

/// The file *is* the export: the same bytes `ExportService` produces for Save
/// and Share, so History can never drift from what the user shared.
///
/// Deals in **file names, never paths**: an iOS container's UUID changes on
/// every reinstall, so a persisted absolute path goes stale.
public protocol CompletionPreviewRepository: Sendable {
    @discardableResult
    func save(_ data: Data, id: UUID) throws -> String
    func data(forFile file: String) throws -> Data
    func delete(file: String) throws
    func deleteAll() throws
}

public final class FileCompletionPreviewRepository: CompletionPreviewRepository, @unchecked Sendable {
    // @unchecked: FileManager is thread-safe for these operations.
    private let directory: URL

    public init(directory: URL? = nil) {
        self.directory = directory
            ?? URL.applicationSupportDirectory.appending(path: "CompletionPreviews")
    }

    @discardableResult
    public func save(_ data: Data, id: UUID) throws -> String {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = "\(id.uuidString).jpg"
        var options: Data.WritingOptions = [.atomic]
        #if os(iOS)
            options.insert(.completeFileProtection)
        #endif
        try data.write(to: directory.appending(path: file), options: options)
        return file
    }

    /// Last path component only, so a name written as a full path still resolves.
    public func data(forFile file: String) throws -> Data {
        try Data(contentsOf: url(file))
    }

    public func delete(file: String) throws {
        let url = url(file)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    public func deleteAll() throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.removeItem(at: directory)
    }

    private func url(_ file: String) -> URL {
        directory.appending(path: URL(filePath: file).lastPathComponent)
    }
}
