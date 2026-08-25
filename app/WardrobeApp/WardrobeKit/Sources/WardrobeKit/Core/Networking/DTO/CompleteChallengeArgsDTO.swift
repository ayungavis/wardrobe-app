import Foundation

struct CompleteChallengeArgsDTO: Encodable, Sendable {
    let completionId: UUID
    let cardId: UUID
    let localDate: String
    let timeZone: String
    let completedAt: Date
    let photo: CompletionPhotoDTO
    let derivative: CompletionDerivativeDTO
    let document: CompletionDocumentDTO
    var layerPhotoIds: [UUID] = []
    var items: [CompletionItemDTO] = []
}

struct CompletionPhotoDTO: Encodable, Sendable {
    let id: UUID
    let mediaObjectId: UUID
    let source: String
    var capturedAt: Date?
}

struct CompletionDerivativeDTO: Encodable, Sendable {
    let id: UUID
    let mediaObjectId: UUID
}

struct CompletionDocumentDTO: Encodable, Sendable {
    let id: UUID
    let schemaVersion: Int32
    let mediaObjectId: UUID
    var historyMediaObjectId: UUID?
    var historyStepCount: Int32?
}

struct CompletionItemDTO: Encodable, Sendable {
    let id: UUID
    let wearId: UUID
    let category: String
    var name: String?
    var color: String?
    var garmentType: String?
    var description: String?
    var sourcePhotoId: UUID?
    var cutout: CutoutArgsDTO?
}
