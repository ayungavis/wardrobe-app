import Foundation
import SwiftData
import Testing
@testable import WardrobeKit

// Shared restore fixtures: one SUT and one JSON builder per feed kind, used by
// the media, illustration, and merge restore suites.

let itemID: UUID = .init(uuid: (0, 0, 0, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, 0x2A))

struct SUT {
    let applier: LocalRestoreService
    let repository: SwiftDataWardrobeItemRepository
    let completions: SwiftDataCompletedChallengeRepository
    let downloads: StoredMediaDownloadRepository
    let media: StubMediaRepository
    let photos: SpyPhotoRepository
    let previews: InMemoryCompletionPreviewRepository
    let thumbnails: InMemoryGarmentThumbnailRepository
}

@MainActor
func makeSUT() throws -> SUT {
    let container = try ModelContainer(
        for: SwiftDataWardrobeItemRepository.schema,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = ModelContext(container)
    let repository = SwiftDataWardrobeItemRepository(context: context)
    let completions = SwiftDataCompletedChallengeRepository(context: context)
    let downloads = StoredMediaDownloadRepository(store: SwiftDataMediaDownloadStore(context: context))
    let media = StubMediaRepository()
    let photos = SpyPhotoRepository()
    let previews = InMemoryCompletionPreviewRepository()
    let thumbnails = InMemoryGarmentThumbnailRepository()
    return SUT(
        applier: LocalRestoreService(
            wardrobe: repository, completions: completions,
            preferences: CountingPreferencesRepository(),
            downloads: downloads, media: media, photos: photos,
            previews: previews, thumbnails: thumbnails
        ),
        repository: repository,
        completions: completions,
        downloads: downloads,
        media: media,
        photos: photos,
        previews: previews,
        thumbnails: thumbnails
    )
}

@MainActor
func page(_ records: [String]) throws -> [ChangeDTO] {
    let entries = records.enumerated().map { index, record in
        "{\"changeSeq\":\(index + 1),\(record)}"
    }
    let json = "{\"changes\":[\(entries.joined(separator: ","))],\"nextSince\":\(records.count)}"
    return try JSONDecoder.api.decode(GetChangesResponseDTO.self, from: Data(json.utf8)).changes
}

@MainActor
func fingerprintJSON(id: UUID, itemID: UUID) -> String {
    #"""
    "kind":"itemFingerprint","record":{"id":"\#(id)","itemId":"\#(itemID)",
     "version":"v1","colorLab":[1,2,3],"aspectRatio":0.75,"featurePrint":"AP8=",
     "maskQuality":0.9,"sourcePhotoId":null,"changeSeq":1,"deletedAt":null}
    """#
}

@MainActor
func conflictJSON(id: UUID, resolvedAt: String?) -> String {
    let stamp = resolvedAt.map { "\"\($0)\"" } ?? "null"
    return #"""
    "kind":"wardrobeItemConflict","record":{"id":"\#(id)","itemId":"\#(itemID)",
     "field":"name","value":"x","revision":1,"originDevice":null,"resolvedAt":\#(stamp),"changeSeq":1}
    """#
}

@MainActor
func itemJSON(illustrationID: UUID? = nil) -> String {
    let pointer = illustrationID.map { "\"\($0)\"" } ?? "null"
    let state = illustrationID == nil ? "none" : "ready"
    return #"""
    "kind":"wardrobeItem","record":{"id":"\#(itemID)","category":"top","name":"coat",
     "color":null,"garmentType":null,"description":null,
     "attributeRevisions":{"name":{"rev":3}},"illustrationState":"\#(state)",
     "currentIllustrationId":\#(pointer),"changeSeq":1,"deletedAt":null}
    """#
}

@MainActor
func illustrationJSON(id: UUID, mediaID: UUID) -> String {
    #"""
    "kind":"itemIllustration","record":{"id":"\#(id)","itemId":"\#(itemID)",
     "mediaObjectId":"\#(mediaID)","model":"m","promptVersion":"p1","styleVersion":"v1",
     "changeSeq":1,"deletedAt":null}
    """#
}

@MainActor
func completionJSON(
    id: UUID = UUID(), status: String = "canonical", derivativeID: UUID? = nil
) -> String {
    let derivative = derivativeID.map { "\"\($0)\"" } ?? "null"
    return #"""
    "kind":"challengeCompletion","record":{"id":"\#(id)","cardId":"\#(UUID())",
     "status":"\#(status)","localDate":"2026-08-25","timeZone":"Asia/Makassar",
     "completedAt":"2026-08-25T09:00:00Z","photoId":null,"currentDerivativeId":\#(derivative),
     "changeSeq":1,"deletedAt":null}
    """#
}

@MainActor
func canvasDocumentJSON(completionID: UUID, schemaVersion: Int = 1, mediaID: UUID = UUID()) -> String {
    #"""
    "kind":"canvasDocument","record":{"id":"\#(UUID())","completionId":"\#(completionID)",
     "derivativeId":"\#(UUID())","schemaVersion":\#(schemaVersion),"mediaObjectId":"\#(mediaID)",
     "historyMediaObjectId":null,"historyStepCount":null,"changeSeq":1,"deletedAt":null}
    """#
}

@MainActor
func derivativeJSON(id: UUID, mediaID: UUID = UUID()) -> String {
    #"""
    "kind":"photoDerivative","record":{"id":"\#(id)","photoId":"\#(UUID())",
     "mediaObjectId":"\#(mediaID)","changeSeq":1,"deletedAt":null}
    """#
}

@MainActor
func photoJSON(id: UUID = UUID(), mediaID: UUID = UUID()) -> String {
    #"""
    "kind":"photo","record":{"id":"\#(id)","mediaObjectId":"\#(mediaID)","source":"camera",
     "capturedAt":null,"changeSeq":1,"deletedAt":null}
    """#
}

@MainActor
func cutoutJSON(mediaID: UUID = UUID()) -> String {
    #"""
    "kind":"itemCutout","record":{"id":"\#(UUID())","itemId":"\#(itemID)",
     "mediaObjectId":"\#(mediaID)","sourcePhotoId":null,"changeSeq":1,"deletedAt":null}
    """#
}
