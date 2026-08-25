import Foundation
import SwiftData
import Testing
@testable import WardrobeKit

@MainActor
struct MediaRestoreTests {
    // MARK: - A fresh device (T45b)

    @Test func aFreshDeviceCompletionBecomesVisibleAwaitingItsDocument() throws {
        let sut = try makeSUT()
        let completionID = UUID()

        try sut.applier.apply(page([completionJSON(id: completionID)]))
        try sut.completions.commitStaged()

        let restored = try #require(sut.completions.load().first)
        #expect(restored.id == completionID)
        #expect(restored.documentState == .pending)
        #expect(restored.status == .canonical)
    }

    @Test func mediaBackedRecordsStageDownloads() throws {
        let sut = try makeSUT()
        let completionID = UUID()
        let derivativeID = UUID()

        try sut.applier.apply(page([
            itemJSON(),
            completionJSON(id: completionID, derivativeID: derivativeID),
            canvasDocumentJSON(completionID: completionID),
            derivativeJSON(id: derivativeID),
            photoJSON(),
            cutoutJSON(),
        ]))
        try sut.repository.commitStaged()

        let staged = try sut.downloads.entries()
        #expect(staged.count == 4, "document, preview, original, cutout")
        let kinds = staged.map(\.destination)
        #expect(kinds.contains {
            if case .completionDocument = $0 {
                true
            } else {
                false
            }
        })
        #expect(kinds.contains {
            if case .completionPreview = $0 {
                true
            } else {
                false
            }
        })
        #expect(kinds.contains {
            if case .photoOriginal = $0 {
                true
            } else {
                false
            }
        })
        #expect(kinds.contains {
            if case .itemCutout = $0 {
                true
            } else {
                false
            }
        })
    }

    @Test func aNewerDocumentIsMarkedUnsupportedWithoutADownload() throws {
        let sut = try makeSUT()
        let completionID = UUID()

        try sut.applier.apply(page([
            completionJSON(id: completionID),
            canvasDocumentJSON(completionID: completionID, schemaVersion: EditorDocument.currentSchemaVersion + 1),
        ]))
        try sut.completions.commitStaged()

        #expect(sut.completions.load().first?.documentState == .unsupported)
        #expect(try sut.downloads.entries().isEmpty)
    }

    @Test func aDerivativeForAnUnknownCompletionStagesNothing() throws {
        let sut = try makeSUT()

        try sut.applier.apply(page([derivativeJSON(id: UUID())]))
        try sut.repository.commitStaged()

        #expect(try sut.downloads.entries().isEmpty)
    }

    // MARK: - The download phase (T45b)

    @Test func oneFailedDownloadDoesNotStallTheOthers() async throws {
        let sut = try makeSUT()
        let failing = UUID()
        let winning = UUID()
        sut.downloads.stage(MediaDownload(id: failing, destination: .photoOriginal(photoID: UUID())))
        sut.downloads.stage(MediaDownload(id: winning, destination: .photoOriginal(photoID: UUID())))
        try sut.repository.commitStaged()
        sut.media.failingIDs = [failing]
        sut.media.downloads[winning] = Data([0x01])

        let outcome = await sut.applier.restoreDueMedia(at: Date())

        #expect(outcome.restored == 1)
        let remaining = try sut.downloads.entries()
        #expect(remaining.count == 1)
        #expect(remaining.first?.id == failing)
        #expect(remaining.first?.attempts == 1)
    }

    @Test func aDownloadedPreviewLandsOnItsCompletion() async throws {
        let sut = try makeSUT()
        let completionID = UUID()
        let derivativeID = UUID()
        let mediaID = UUID()
        try sut.applier.apply(page([
            completionJSON(id: completionID, derivativeID: derivativeID),
            derivativeJSON(id: derivativeID, mediaID: mediaID),
        ]))
        try sut.completions.commitStaged()
        sut.media.downloads[mediaID] = Data([0xFF])

        _ = await sut.applier.restoreDueMedia(at: Date())

        #expect(sut.completions.load().first?.previewFile != nil)
        #expect(try sut.downloads.entries().isEmpty)
    }

    @Test func aDownloadedDocumentFlipsTheStateToAvailable() async throws {
        let sut = try makeSUT()
        let completionID = UUID()
        let mediaID = UUID()
        try sut.applier.apply(page([
            completionJSON(id: completionID),
            canvasDocumentJSON(completionID: completionID, mediaID: mediaID),
        ]))
        try sut.completions.commitStaged()
        sut.media.downloads[mediaID] = try JSONEncoder().encode(EditorDocument(id: UUID(), layers: []))

        _ = await sut.applier.restoreDueMedia(at: Date())

        #expect(sut.completions.load().first?.documentState == .available)
    }

    @Test func aNewerDocumentAtDownloadTimeIsUnsupportedAndDropped() async throws {
        let sut = try makeSUT()
        let completionID = UUID()
        let mediaID = UUID()
        try sut.applier.apply(page([
            completionJSON(id: completionID),
            canvasDocumentJSON(completionID: completionID, mediaID: mediaID),
        ]))
        try sut.completions.commitStaged()
        let newer = #"{"id":"\#(UUID.v7())","schemaVersion":\#(EditorDocument.currentSchemaVersion + 1),"layers":[]}"#
        sut.media.downloads[mediaID] = Data(newer.utf8)

        _ = await sut.applier.restoreDueMedia(at: Date())

        #expect(sut.completions.load().first?.documentState == .unsupported)
        #expect(try sut.downloads.entries().isEmpty, "an unusable document must not retry forever")
    }

    @Test func aReplayedStagingKeepsOneRowAndItsBackoff() throws {
        let sut = try makeSUT()
        let mediaID = UUID()
        sut.downloads.stage(MediaDownload(id: mediaID, destination: .photoOriginal(photoID: UUID())))
        try sut.repository.commitStaged()
        try sut.downloads.recordFailure(of: mediaID, error: .unavailable, code: nil, at: Date())

        sut.downloads.stage(MediaDownload(id: mediaID, destination: .photoOriginal(photoID: UUID())))
        try sut.repository.commitStaged()

        let rows = try sut.downloads.entries()
        #expect(rows.count == 1)
        #expect(rows.first?.attempts == 1, "a replayed feed page must not reset the backoff")
    }

    // MARK: - Fixtures

    private let itemID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, 0x2A))

    private struct SUT {
        let applier: LocalRestoreService
        let repository: SwiftDataWardrobeItemRepository
        let completions: SwiftDataCompletedChallengeRepository
        let downloads: StoredMediaDownloadRepository
        let media: StubMediaRepository
        let photos: SpyPhotoRepository
        let previews: InMemoryCompletionPreviewRepository
        let thumbnails: InMemoryGarmentThumbnailRepository
    }

    private func makeSUT() throws -> SUT {
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

    private func page(_ records: [String]) throws -> [ChangeDTO] {
        let entries = records.enumerated().map { index, record in
            "{\"changeSeq\":\(index + 1),\(record)}"
        }
        let json = "{\"changes\":[\(entries.joined(separator: ","))],\"nextSince\":\(records.count)}"
        return try JSONDecoder.api.decode(GetChangesResponseDTO.self, from: Data(json.utf8)).changes
    }

    private func itemJSON() -> String {
        #"""
        "kind":"wardrobeItem","record":{"id":"\#(itemID)","category":"top","name":"coat",
         "color":null,"garmentType":null,"description":null,
         "attributeRevisions":{"name":{"rev":3}},"illustrationState":"none",
         "currentIllustrationId":null,"changeSeq":1,"deletedAt":null}
        """#
    }

    private func completionJSON(
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

    private func canvasDocumentJSON(completionID: UUID, schemaVersion: Int = 1, mediaID: UUID = UUID()) -> String {
        #"""
        "kind":"canvasDocument","record":{"id":"\#(UUID())","completionId":"\#(completionID)",
         "derivativeId":"\#(UUID())","schemaVersion":\#(schemaVersion),"mediaObjectId":"\#(mediaID)",
         "historyMediaObjectId":null,"historyStepCount":null,"changeSeq":1,"deletedAt":null}
        """#
    }

    private func derivativeJSON(id: UUID, mediaID: UUID = UUID()) -> String {
        #"""
        "kind":"photoDerivative","record":{"id":"\#(id)","photoId":"\#(UUID())",
         "mediaObjectId":"\#(mediaID)","changeSeq":1,"deletedAt":null}
        """#
    }

    private func photoJSON(id: UUID = UUID(), mediaID: UUID = UUID()) -> String {
        #"""
        "kind":"photo","record":{"id":"\#(id)","mediaObjectId":"\#(mediaID)","source":"camera",
         "capturedAt":null,"changeSeq":1,"deletedAt":null}
        """#
    }

    private func cutoutJSON(mediaID: UUID = UUID()) -> String {
        #"""
        "kind":"itemCutout","record":{"id":"\#(UUID())","itemId":"\#(itemID)",
         "mediaObjectId":"\#(mediaID)","sourcePhotoId":null,"changeSeq":1,"deletedAt":null}
        """#
    }
}
