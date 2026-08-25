import Foundation

public enum MediaUploadSource: Sendable, Equatable, Hashable {
    case photoOriginal(UUID)
    case previewFile(String)
    case thumbnailFile(String)
    case inline(Data)
}

public struct MediaUpload: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let ownerID: UUID
    public let kind: MediaKind
    public let contentType: String
    public let source: MediaUploadSource
    public let createdAt: Date
    public var attempts: Int
    public var state: OutboxEnvelope.State
    public var nextAttemptAt: Date
    public var lastErrorCode: String?

    public init(
        id: UUID,
        ownerID: UUID,
        kind: MediaKind,
        contentType: String,
        source: MediaUploadSource,
        createdAt: Date,
        attempts: Int = 0,
        state: OutboxEnvelope.State = .pending,
        nextAttemptAt: Date? = nil,
        lastErrorCode: String? = nil
    ) {
        self.id = id
        self.ownerID = ownerID
        self.kind = kind
        self.contentType = contentType
        self.source = source
        self.createdAt = createdAt
        self.attempts = attempts
        self.state = state
        self.nextAttemptAt = nextAttemptAt ?? createdAt
        self.lastErrorCode = lastErrorCode
    }
}
