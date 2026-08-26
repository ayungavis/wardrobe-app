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

    // MARK: - Rows the server moved in a merge (T46)

    @Test func aMovedFingerprintFollowsItsNewItem() throws {
        let sut = try makeSUT()
        let fingerprintID = UUID()
        let newItemID = UUID()
        try sut.applier.apply(page([fingerprintJSON(id: fingerprintID, itemID: itemID)]))
        try sut.repository.commitStaged()

        try sut.applier.apply(page([fingerprintJSON(id: fingerprintID, itemID: newItemID)]))
        try sut.repository.commitStaged()

        let owners = try sut.repository.fingerprints().map(\.itemID)
        #expect(owners == [newItemID],
                "a fingerprint the server moved must follow, or the survivor loses it forever")
    }

    @Test func aReplayedConflictCarriesItsResolution() throws {
        let sut = try makeSUT()
        let conflictID = UUID()
        try sut.applier.apply(page([conflictJSON(id: conflictID, resolvedAt: nil)]))
        try sut.repository.commitStaged()
        #expect(try sut.repository.openConflicts().count == 1)

        try sut.applier.apply(page([conflictJSON(id: conflictID, resolvedAt: "2026-08-25T12:00:00Z")]))
        try sut.repository.commitStaged()

        #expect(try sut.repository.openConflicts().isEmpty,
                "the server said this conflict is settled; the client must not keep it open")
    }
}

// MARK: - Fixtures
