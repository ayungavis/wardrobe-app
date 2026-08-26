import Foundation
import SwiftData

@MainActor
public protocol MediaUploadStore: AnyObject {
    func stage(_ upload: MediaUpload)
    func all() throws -> [MediaUpload]
    func due(at date: Date, limit: Int) throws -> [MediaUpload]
    func hasRows(owner: UUID) throws -> Bool
    func update(_ upload: MediaUpload) throws
    func remove(id: UUID) throws
    func removeAll() throws
}

// MARK: - SwiftData

@MainActor
public final class SwiftDataMediaUploadStore: MediaUploadStore {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public func stage(_ upload: MediaUpload) {
        context.insert(MediaUploadEntity(upload))
    }

    public func all() throws -> [MediaUpload] {
        try context.fetch(Self.ordered()).compactMap(\.domain)
    }

    public func due(at date: Date, limit: Int) throws -> [MediaUpload] {
        let pending = OutboxEnvelope.State.pending.rawValue
        var descriptor = Self.ordered(
            matching: #Predicate { $0.state == pending && $0.nextAttemptAt <= date }
        )
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor).compactMap(\.domain)
    }

    public func hasRows(owner: UUID) throws -> Bool {
        var descriptor = FetchDescriptor<MediaUploadEntity>(predicate: #Predicate { $0.ownerID == owner })
        descriptor.fetchLimit = 1
        return try context.fetchCount(descriptor) > 0
    }

    public func update(_ upload: MediaUpload) throws {
        let id = upload.id
        guard let entity = try context.fetch(
            FetchDescriptor<MediaUploadEntity>(predicate: #Predicate { $0.id == id })
        ).first else {
            throw AppError.unexpected
        }
        entity.apply(upload)
        try context.save()
    }

    public func remove(id: UUID) throws {
        try context.delete(model: MediaUploadEntity.self, where: #Predicate { $0.id == id })
        try context.save()
    }

    public func removeAll() throws {
        try context.delete(model: MediaUploadEntity.self)
        try context.save()
    }

    private static func ordered(
        matching predicate: Predicate<MediaUploadEntity>? = nil
    ) -> FetchDescriptor<MediaUploadEntity> {
        FetchDescriptor<MediaUploadEntity>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
    }
}

// MARK: - Storage entity

@Model
final class MediaUploadEntity {
    #Unique<MediaUploadEntity>([\.id])
    private(set) var id: UUID = UUID()
    var ownerID: UUID = UUID()
    var kind: String = MediaKind.original.rawValue
    var contentType: String = ""
    var sourceKind: String = ""
    var sourceRef: String = ""
    var inlineData: Data?
    var createdAt: Date = Date()
    var attempts: Int = 0
    var state: String = OutboxEnvelope.State.pending.rawValue
    var nextAttemptAt: Date = Date()
    var lastErrorCode: String?

    init(_ upload: MediaUpload) {
        id = upload.id
        ownerID = upload.ownerID
        kind = upload.kind.rawValue
        contentType = upload.contentType
        createdAt = upload.createdAt
        switch upload.source {
        case let .photoOriginal(photoID):
            sourceKind = "photoOriginal"
            sourceRef = photoID.uuidString
        case let .previewFile(file):
            sourceKind = "previewFile"
            sourceRef = file
        case let .thumbnailFile(file):
            sourceKind = "thumbnailFile"
            sourceRef = file
        case let .inline(data):
            sourceKind = "inline"
            inlineData = data
        }
        apply(upload)
    }

    func apply(_ upload: MediaUpload) {
        attempts = upload.attempts
        state = upload.state.rawValue
        nextAttemptAt = upload.nextAttemptAt
        lastErrorCode = upload.lastErrorCode
    }

    var domain: MediaUpload? {
        guard let kind = MediaKind(rawValue: kind), let source else { return nil }
        return MediaUpload(
            id: id, ownerID: ownerID, kind: kind, contentType: contentType,
            source: source, createdAt: createdAt, attempts: attempts,
            state: OutboxEnvelope.State(rawValue: state) ?? .pending,
            nextAttemptAt: nextAttemptAt, lastErrorCode: lastErrorCode
        )
    }

    private var source: MediaUploadSource? {
        switch sourceKind {
        case "photoOriginal": UUID(uuidString: sourceRef).map(MediaUploadSource.photoOriginal)
        case "previewFile": .previewFile(sourceRef)
        case "thumbnailFile": .thumbnailFile(sourceRef)
        case "inline": inlineData.map(MediaUploadSource.inline)
        default: nil
        }
    }
}
