import Foundation

struct GetChangesResponseDTO: Decodable, Sendable {
    let changes: [ChangeDTO]
    let nextSince: Int64
}

struct ChangeDTO: Decodable, Sendable {
    let changeSeq: Int64
    let record: ChangeRecordDTO

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        changeSeq = try container.decode(Int64.self, forKey: .changeSeq)
        record = try ChangeRecordDTO(from: decoder)
    }

    private enum CodingKeys: String, CodingKey {
        case changeSeq
    }
}

enum ChangeRecordDTO: Decodable, Sendable {
    case wardrobeItem(WardrobeItemRecordDTO)
    case itemFingerprint(ItemFingerprintRecordDTO)
    case itemCutout(ItemCutoutRecordDTO)
    case itemIllustration(ItemIllustrationRecordDTO)
    case wardrobeItemConflict(WardrobeItemConflictRecordDTO)
    case photo(PhotoRecordDTO)
    case photoDerivative(PhotoDerivativeRecordDTO)
    case canvasDocument(CanvasDocumentRecordDTO)
    case challengeCompletion(ChallengeCompletionRecordDTO)
    case activeChallenge(ActiveChallengeRecordDTO)
    case wearRecord(WearRecordRecordDTO)
    case accountPreference(AccountPreferenceRecordDTO)
    case unrecognised(kind: String)

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        if let wardrobe = try Self.wardrobeKind(kind, in: container) {
            self = wardrobe
        } else if let capture = try Self.captureKind(kind, in: container) {
            self = capture
        } else {
            self = .unrecognised(kind: kind)
        }
    }

    private static func wardrobeKind(
        _ kind: String, in container: KeyedDecodingContainer<CodingKeys>
    ) throws -> ChangeRecordDTO? {
        switch kind {
        case "wardrobeItem": try .wardrobeItem(container.decode(WardrobeItemRecordDTO.self, forKey: .record))
        case "itemFingerprint": try .itemFingerprint(container.decode(ItemFingerprintRecordDTO.self, forKey: .record))
        case "itemCutout": try .itemCutout(container.decode(ItemCutoutRecordDTO.self, forKey: .record))
        case "itemIllustration":
            try .itemIllustration(container.decode(ItemIllustrationRecordDTO.self, forKey: .record))
        case "wardrobeItemConflict":
            try .wardrobeItemConflict(container.decode(WardrobeItemConflictRecordDTO.self, forKey: .record))
        case "wearRecord": try .wearRecord(container.decode(WearRecordRecordDTO.self, forKey: .record))
        default: nil
        }
    }

    private static func captureKind(
        _ kind: String, in container: KeyedDecodingContainer<CodingKeys>
    ) throws -> ChangeRecordDTO? {
        switch kind {
        case "photo": try .photo(container.decode(PhotoRecordDTO.self, forKey: .record))
        case "photoDerivative": try .photoDerivative(container.decode(PhotoDerivativeRecordDTO.self, forKey: .record))
        case "canvasDocument": try .canvasDocument(container.decode(CanvasDocumentRecordDTO.self, forKey: .record))
        case "challengeCompletion":
            try .challengeCompletion(container.decode(ChallengeCompletionRecordDTO.self, forKey: .record))
        case "activeChallenge": try .activeChallenge(container.decode(ActiveChallengeRecordDTO.self, forKey: .record))
        case "accountPreference": try .accountPreference(container.decode(AccountPreferenceRecordDTO.self, forKey: .record))
        default: nil
        }
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case record
    }
}

struct WardrobeItemRecordDTO: Decodable, Sendable {
    let id: UUID
    let category: String
    let name: String?
    let color: String?
    let garmentType: String?
    let description: String?
    let attributeRevisions: JSONValue
    let illustrationState: String
    let currentIllustrationId: UUID?
    let changeSeq: Int64
    let deletedAt: Date?
}

struct ItemFingerprintRecordDTO: Decodable, Sendable {
    let id: UUID
    let itemId: UUID
    let version: String
    let colorLab: [Double]
    let aspectRatio: Double
    let featurePrint: Data
    let maskQuality: Double
    let sourcePhotoId: UUID?
    let changeSeq: Int64
    let deletedAt: Date?
}

struct ItemCutoutRecordDTO: Decodable, Sendable {
    let id: UUID
    let itemId: UUID
    let mediaObjectId: UUID
    let sourcePhotoId: UUID?
    let changeSeq: Int64
    let deletedAt: Date?
}

struct ItemIllustrationRecordDTO: Decodable, Sendable {
    let id: UUID
    let itemId: UUID
    let mediaObjectId: UUID
    let model: String
    let promptVersion: String
    let styleVersion: String
    let changeSeq: Int64
    let deletedAt: Date?
}

struct WardrobeItemConflictRecordDTO: Decodable, Sendable {
    let id: UUID
    let itemId: UUID
    let field: String
    let value: String?
    let revision: Int64
    let originDevice: UUID?
    let resolvedAt: Date?
    let changeSeq: Int64
}

struct PhotoRecordDTO: Decodable, Sendable {
    let id: UUID
    let mediaObjectId: UUID
    let source: String
    let capturedAt: Date?
    let changeSeq: Int64
    let deletedAt: Date?
}

struct PhotoDerivativeRecordDTO: Decodable, Sendable {
    let id: UUID
    let photoId: UUID
    let mediaObjectId: UUID
    let changeSeq: Int64
    let deletedAt: Date?
}

struct CanvasDocumentRecordDTO: Decodable, Sendable {
    let id: UUID
    let completionId: UUID
    let derivativeId: UUID
    let schemaVersion: Int32
    let mediaObjectId: UUID
    let historyMediaObjectId: UUID?
    let historyStepCount: Int32?
    let changeSeq: Int64
    let deletedAt: Date?
}

struct ChallengeCompletionRecordDTO: Decodable, Sendable {
    let id: UUID
    let cardId: UUID
    let status: String
    let localDate: String
    let timeZone: String
    let completedAt: Date
    let photoId: UUID?
    let currentDerivativeId: UUID?
    let changeSeq: Int64
    let deletedAt: Date?
}

struct ActiveChallengeRecordDTO: Decodable, Sendable {
    let id: UUID
    let cardId: UUID
    let localDate: String
    let timeZone: String
    let acceptedAt: Date
    let photoId: UUID?
    let changeSeq: Int64
    let deletedAt: Date?
}

struct WearRecordRecordDTO: Decodable, Sendable {
    let id: UUID
    let itemId: UUID
    let wornOn: String
    let revision: Int32
    let completionId: UUID?
    let sourcePhotoId: UUID?
    let changeSeq: Int64
    let deletedAt: Date?
}

struct AccountPreferenceRecordDTO: Decodable, Sendable {
    let recentStickerIds: [String]
    let lastTextStyle: JSONValue
    let onboardingCompletedAt: Date?
    let uploadConsentAt: Date?
    let changeSeq: Int64
    let deletedAt: Date?
}
