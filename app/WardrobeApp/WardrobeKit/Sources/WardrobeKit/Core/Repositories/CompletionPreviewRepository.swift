import Foundation

public protocol CompletionPreviewRepository: Sendable {
    @discardableResult
    func save(_ data: Data, id: UUID) throws -> String
    func data(forFile file: String) throws -> Data
    func delete(file: String) throws
    func deleteAll() throws
}

public final class FileCompletionPreviewRepository: CompletionPreviewRepository, @unchecked Sendable {
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
