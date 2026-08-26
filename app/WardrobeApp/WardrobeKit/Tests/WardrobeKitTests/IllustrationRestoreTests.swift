import Foundation
import SwiftData
import Testing
@testable import WardrobeKit

@MainActor
struct IllustrationRestoreTests {
    @Test func anItemNobodyEverQueuedIsNotWaitingForAnything() throws {
        let sut = try makeSUT()

        try sut.applier.apply(page([itemJSON(illustrationState: "none")]))
        try sut.repository.commitStaged()

        #expect(try sut.repository.items().first?.status == ItemStatus.undrawn,
                "promising a drawing that no job will ever make is a lie the screen tells")
    }

    @Test func aPulledItemCarriesWhereItsIllustrationGotTo() throws {
        let sut = try makeSUT()

        try sut.applier.apply(page([itemJSON(illustrationState: "failed")]))
        try sut.repository.commitStaged()

        #expect(try sut.repository.items().first?.status == .failed,
                "a screen that cannot see a failure cannot offer to fix it")
    }

    @Test func aPulledItemKeepsItsIllustrationPointer() throws {
        let sut = try makeSUT()
        let illustrationID = UUID()

        try sut.applier.apply(page([itemJSON(illustrationID: illustrationID)]))
        try sut.repository.commitStaged()

        #expect(try sut.repository.items().first?.currentIllustrationID == illustrationID,
                "the pointer is what lets the wardrobe swap the cut-out for the illustration")
    }

    @Test func anIllustrationRecordStagesItsDownload() throws {
        let sut = try makeSUT()
        let illustrationID = UUID()
        let mediaID = UUID()

        try sut.applier.apply(page([
            itemJSON(illustrationID: illustrationID),
            illustrationJSON(id: illustrationID, mediaID: mediaID),
        ]))
        try sut.repository.commitStaged()

        let staged = try sut.downloads.entries()
        #expect(staged.map(\.id) == [mediaID])
        #expect(staged.first?.destination == .itemIllustration(illustrationID: illustrationID))
    }

    @Test func aDownloadedIllustrationLandsUnderItsOwnId() async throws {
        let sut = try makeSUT()
        let illustrationID = UUID()
        let mediaID = UUID()
        sut.downloads.stage(MediaDownload(
            id: mediaID, destination: .itemIllustration(illustrationID: illustrationID)
        ))
        try sut.repository.commitStaged()
        sut.media.downloads[mediaID] = Data([0x89, 0x50])

        _ = await sut.applier.restoreDueMedia(at: Date())

        #expect(try sut.thumbnails.data(forFile: "\(illustrationID.uuidString).png") == Data([0x89, 0x50]))
        #expect(try sut.downloads.entries().isEmpty)
    }

    @Test func anIllustrationThatArrivesBeforeItsItemIsStillQueued() throws {
        let sut = try makeSUT()
        let illustrationID = UUID()
        let mediaID = UUID()

        try sut.applier.apply(page([illustrationJSON(id: illustrationID, mediaID: mediaID)]))
        try sut.repository.commitStaged()

        #expect(try sut.downloads.entries().map(\.id) == [mediaID],
                "the cursor moves past a dropped record forever; order inside a page is not ours to assume")
    }
}
