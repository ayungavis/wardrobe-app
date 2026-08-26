import Foundation

public enum MediaDownloadDestination: Sendable, Equatable, Hashable {
    case completionPreview(completionID: UUID)
    case completionDocument(completionID: UUID)
    case photoOriginal(photoID: UUID)
    case itemCutout(itemID: UUID)
    case itemIllustration(illustrationID: UUID)
    case outfitTemplate(requestID: UUID)
}

public struct MediaDownload: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let destination: MediaDownloadDestination
    public let createdAt: Date
    public var attempts: Int
    public var state: OutboxEnvelope.State
    public var nextAttemptAt: Date
    public var lastErrorCode: String?

    public init(id: UUID, destination: MediaDownloadDestination, createdAt: Date = Date()) {
        self.id = id
        self.destination = destination
        self.createdAt = createdAt
        attempts = 0
        state = .pending
        nextAttemptAt = createdAt
        lastErrorCode = nil
    }
}
