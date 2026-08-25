import Foundation

@MainActor
public protocol MediaUploadRepository: AnyObject {
    func stage(_ upload: MediaUpload)
    func entries() throws -> [MediaUpload]
    func due(at date: Date, limit: Int) throws -> [MediaUpload]
    func holdsRows(owner: UUID) throws -> Bool
    func bytes(for upload: MediaUpload) throws -> Data
    func acknowledge(id: UUID) throws
    func recordFailure(of id: UUID, error: AppError, code: String?, at date: Date) throws
    func retryFailed(at date: Date) throws
    func removeAll() throws
}

@MainActor
public final class StoredMediaUploadRepository: MediaUploadRepository {
    private let store: any MediaUploadStore
    private let photos: any PhotoRepository
    private let previews: any CompletionPreviewRepository
    private let thumbnails: any GarmentThumbnailRepository

    public init(
        store: any MediaUploadStore,
        photos: any PhotoRepository,
        previews: any CompletionPreviewRepository,
        thumbnails: any GarmentThumbnailRepository
    ) {
        self.store = store
        self.photos = photos
        self.previews = previews
        self.thumbnails = thumbnails
    }

    public func stage(_ upload: MediaUpload) {
        store.stage(upload)
    }

    public func entries() throws -> [MediaUpload] {
        try store.all()
    }

    public func due(at date: Date, limit: Int) throws -> [MediaUpload] {
        try store.due(at: date, limit: limit)
    }

    public func holdsRows(owner: UUID) throws -> Bool {
        try store.hasRows(owner: owner)
    }

    public func bytes(for upload: MediaUpload) throws -> Data {
        switch upload.source {
        case let .photoOriginal(photoID):
            try photos.loadOriginal(id: photoID)
        case let .previewFile(file):
            try previews.data(forFile: file)
        case let .thumbnailFile(file):
            try thumbnails.data(forFile: file)
        case let .inline(data):
            data
        }
    }

    public func acknowledge(id: UUID) throws {
        try store.remove(id: id)
    }

    public func recordFailure(of id: UUID, error: AppError, code: String?, at date: Date) throws {
        guard var upload = try store.all().first(where: { $0.id == id }) else {
            throw AppError.unexpected
        }

        upload.attempts += 1
        upload.lastErrorCode = code ?? StoredOutboxRepository.code(for: error)
        if upload.attempts >= StoredOutboxRepository.maxAttempts {
            upload.state = .failed
        } else {
            upload.nextAttemptAt = date.addingTimeInterval(
                StoredOutboxRepository.delay(afterAttempt: upload.attempts)
            )
        }
        try store.update(upload)
    }

    public func retryFailed(at date: Date) throws {
        for var upload in try store.all() where upload.state == .failed {
            upload.state = .pending
            upload.attempts = 0
            upload.nextAttemptAt = date
            try store.update(upload)
        }
    }

    public func removeAll() throws {
        try store.removeAll()
    }
}
