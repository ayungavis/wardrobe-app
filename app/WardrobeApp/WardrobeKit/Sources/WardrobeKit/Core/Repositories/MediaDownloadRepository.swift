import Foundation

@MainActor
public protocol MediaDownloadRepository: AnyObject {
    func stage(_ download: MediaDownload)
    func entries() throws -> [MediaDownload]
    func due(at date: Date, limit: Int) throws -> [MediaDownload]
    func acknowledge(id: UUID) throws
    func recordFailure(of id: UUID, error: AppError, code: String?, at date: Date) throws
    func retryFailed(at date: Date) throws
    func removeAll() throws
}

@MainActor
public final class StoredMediaDownloadRepository: MediaDownloadRepository {
    private let store: any MediaDownloadStore

    public init(store: any MediaDownloadStore) {
        self.store = store
    }

    public func stage(_ download: MediaDownload) {
        let staged = (try? store.all()) ?? []
        guard !staged.contains(where: { $0.id == download.id }) else { return }
        store.stage(download)
    }

    public func entries() throws -> [MediaDownload] {
        try store.all()
    }

    public func due(at date: Date, limit: Int) throws -> [MediaDownload] {
        try store.due(at: date, limit: limit)
    }

    public func acknowledge(id: UUID) throws {
        try store.remove(id: id)
    }

    public func recordFailure(of id: UUID, error: AppError, code: String?, at date: Date) throws {
        guard var download = try store.all().first(where: { $0.id == id }) else {
            throw AppError.unexpected
        }

        download.attempts += 1
        download.lastErrorCode = code ?? StoredOutboxRepository.code(for: error)
        if download.attempts >= StoredOutboxRepository.maxAttempts {
            download.state = .failed
        } else {
            download.nextAttemptAt = date.addingTimeInterval(
                StoredOutboxRepository.delay(afterAttempt: download.attempts)
            )
        }
        try store.update(download)
    }

    public func retryFailed(at date: Date) throws {
        for var download in try store.all() where download.state == .failed {
            download.state = .pending
            download.attempts = 0
            download.nextAttemptAt = date
            try store.update(download)
        }
    }

    public func removeAll() throws {
        try store.removeAll()
    }
}
