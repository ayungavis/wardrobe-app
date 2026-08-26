import Foundation
import SwiftData

@MainActor
public protocol MediaDownloadStore: AnyObject {
    func stage(_ download: MediaDownload)
    func all() throws -> [MediaDownload]
    func due(at date: Date, limit: Int) throws -> [MediaDownload]
    func update(_ download: MediaDownload) throws
    func remove(id: UUID) throws
    func removeAll() throws
}

// MARK: - SwiftData

@MainActor
public final class SwiftDataMediaDownloadStore: MediaDownloadStore {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public func stage(_ download: MediaDownload) {
        context.insert(MediaDownloadEntity(download))
    }

    public func all() throws -> [MediaDownload] {
        try context.fetch(Self.ordered()).compactMap(\.domain)
    }

    public func due(at date: Date, limit: Int) throws -> [MediaDownload] {
        let pending = OutboxEnvelope.State.pending.rawValue
        var descriptor = Self.ordered(
            matching: #Predicate { $0.state == pending && $0.nextAttemptAt <= date }
        )
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor).compactMap(\.domain)
    }

    public func update(_ download: MediaDownload) throws {
        let id = download.id
        guard let entity = try context.fetch(
            FetchDescriptor<MediaDownloadEntity>(predicate: #Predicate { $0.id == id })
        ).first else {
            throw AppError.unexpected
        }
        entity.apply(download)
        try context.save()
    }

    public func remove(id: UUID) throws {
        try context.delete(model: MediaDownloadEntity.self, where: #Predicate { $0.id == id })
        try context.save()
    }

    public func removeAll() throws {
        try context.delete(model: MediaDownloadEntity.self)
        try context.save()
    }

    private static func ordered(
        matching predicate: Predicate<MediaDownloadEntity>? = nil
    ) -> FetchDescriptor<MediaDownloadEntity> {
        FetchDescriptor<MediaDownloadEntity>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
    }
}

// MARK: - Storage entity

@Model
final class MediaDownloadEntity {
    #Unique<MediaDownloadEntity>([\.id])
    private(set) var id: UUID = UUID()
    var destinationKind: String = ""
    var destinationRef: UUID = UUID()
    var createdAt: Date = Date()
    var attempts: Int = 0
    var state: String = OutboxEnvelope.State.pending.rawValue
    var nextAttemptAt: Date = Date()
    var lastErrorCode: String?

    init(_ download: MediaDownload) {
        id = download.id
        createdAt = download.createdAt
        switch download.destination {
        case let .completionPreview(completionID):
            destinationKind = "completionPreview"
            destinationRef = completionID
        case let .completionDocument(completionID):
            destinationKind = "completionDocument"
            destinationRef = completionID
        case let .photoOriginal(photoID):
            destinationKind = "photoOriginal"
            destinationRef = photoID
        case let .itemCutout(itemID):
            destinationKind = "itemCutout"
            destinationRef = itemID
        case let .itemIllustration(illustrationID):
            destinationKind = "itemIllustration"
            destinationRef = illustrationID
        case let .outfitTemplate(requestID):
            destinationKind = "outfitTemplate"
            destinationRef = requestID
        }
        apply(download)
    }

    func apply(_ download: MediaDownload) {
        attempts = download.attempts
        state = download.state.rawValue
        nextAttemptAt = download.nextAttemptAt
        lastErrorCode = download.lastErrorCode
    }

    var domain: MediaDownload? {
        let destination: MediaDownloadDestination? = switch destinationKind {
        case "completionPreview": .completionPreview(completionID: destinationRef)
        case "completionDocument": .completionDocument(completionID: destinationRef)
        case "photoOriginal": .photoOriginal(photoID: destinationRef)
        case "itemCutout": .itemCutout(itemID: destinationRef)
        case "itemIllustration": .itemIllustration(illustrationID: destinationRef)
        case "outfitTemplate": .outfitTemplate(requestID: destinationRef)
        default: nil
        }
        guard let destination else { return nil }
        var download = MediaDownload(id: id, destination: destination, createdAt: createdAt)
        download.attempts = attempts
        download.state = OutboxEnvelope.State(rawValue: state) ?? .pending
        download.nextAttemptAt = nextAttemptAt
        download.lastErrorCode = lastErrorCode
        return download
    }
}
