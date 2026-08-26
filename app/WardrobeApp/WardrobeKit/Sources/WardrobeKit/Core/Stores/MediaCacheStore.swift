import Foundation

public protocol MediaCacheStore: Sendable {
    func data(for id: UUID) -> Data?
    func store(_ data: Data, for id: UUID) throws
    func removeAll() throws
}

public struct FileMediaCacheStore: MediaCacheStore {
    private let directory: URL

    public init(directory: URL? = nil) {
        self.directory = directory ?? URL.cachesDirectory.appending(path: "media")
    }

    public func data(for id: UUID) -> Data? {
        try? Data(contentsOf: file(id))
    }

    public func store(_ data: Data, for id: UUID) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: file(id), options: .atomic)
    }

    public func removeAll() throws {
        guard FileManager.default.fileExists(atPath: directory.path()) else { return }
        try FileManager.default.removeItem(at: directory)
    }

    private func file(_ id: UUID) -> URL {
        directory.appending(path: id.uuidString.lowercased())
    }
}
