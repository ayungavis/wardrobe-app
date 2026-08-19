import Foundation

/// Stores the rendered composition of a completed challenge — what History
/// shows instead of the raw capture.
///
/// The file *is* the export: the same bytes `ExportService` produces for Save
/// and Share, so what History shows can never drift from what the user shared.
///
/// Like `GarmentThumbnailRepository`, the API deals in **file names, never
/// paths**: an iOS container's UUID changes on every reinstall, so a persisted
/// absolute path points at a directory that no longer exists.
public protocol CompletionPreviewRepository: Sendable {
    /// Returns the file name to persist — never a path.
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

    /// Takes `Data` rather than a `CGImage` for two reasons: `ExportService`
    /// already hands back encoded JPEG, and only a `Data` write can carry
    /// `.completeFileProtection` (§18.4) — `CGImageDestination` has no way to
    /// ask for it. `FilePhotoRepository` writes originals the same way.
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

    /// Takes the last path component, so a name written before this rule —
    /// holding a full path into a dead container — still resolves as long as
    /// the file itself survived.
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
