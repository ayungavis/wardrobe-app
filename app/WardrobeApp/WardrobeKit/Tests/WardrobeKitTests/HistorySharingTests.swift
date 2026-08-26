import CoreImage
import Foundation
import Testing
@testable import WardrobeKit

@MainActor
struct HistorySharingTests {
    private struct Setup {
        let sut: HistoryViewModel
        let completion: CompletedChallenge
        let saver: SpyPhotoLibrarySaver
        let media: StubMediaRepository?
    }

    private func makeSUT(
        preview: Data? = Data([0xAA, 0xBB]),
        saver: SpyPhotoLibrarySaver = SpyPhotoLibrarySaver(),
        media: StubMediaRepository? = StubMediaRepository()
    ) throws -> Setup {
        let previews = InMemoryCompletionPreviewRepository()
        let completedRepository = InMemoryCompletedChallengeRepository()
        var completion = CompletedChallenge(
            card: ChallengeCard(prompt: "x"), photoID: id("photo-1"),
            document: .fixture(photoID: id("photo-1")), completedAt: Date()
        )
        if let preview {
            completion.previewFile = try previews.save(preview, id: UUID())
        }
        completedRepository.stored = [completion]

        let sut = HistoryViewModel(
            completedRepository: completedRepository,
            outbox: StoredOutboxRepository(store: InMemoryOutboxStore()),
            uploads: makeInMemoryUploads(),
            photoRepository: SpyPhotoRepository(),
            wardrobeRepository: InMemoryWardrobeItemRepository(),
            thumbnails: InMemoryGarmentThumbnailRepository(),
            previews: previews,
            saver: saver,
            media: media
        )
        sut.load()
        return Setup(sut: sut, completion: completion, saver: saver, media: media)
    }

    @Test func savingWritesThePreviewToThePhotoLibrary() async throws {
        let setup = try makeSUT()

        setup.sut.save(setup.completion)
        await setup.sut.shareTask?.value

        #expect(setup.saver.saved == [Data([0xAA, 0xBB])])
        #expect(setup.sut.didSave)
    }

    @Test func savingWithoutAPreviewReportsInsteadOfFailingSilently() async throws {
        let setup = try makeSUT(preview: nil)

        setup.sut.save(setup.completion)
        await setup.sut.shareTask?.value

        #expect(setup.saver.saved.isEmpty, "there is nothing to write, so nothing may be written")
        #expect(setup.sut.alertError != nil, "a silent no-op reads as a broken button")
    }

    @Test func sharingUploadsThePreviewThenAsksForItsURL() async throws {
        let setup = try makeSUT()
        let media = try #require(setup.media)

        setup.sut.share(setup.completion)
        await setup.sut.shareTask?.value

        #expect(media.uploadedIDs.count == 1)
        #expect(media.urlRequests == media.uploadedIDs, "the link has to point at the object just uploaded")
        guard case let .loaded(share) = setup.sut.share else {
            Issue.record("expected a loaded share, got \(setup.sut.share)")
            return
        }
        #expect(share.url.absoluteString.contains(media.uploadedIDs[0].uuidString))
        #expect(setup.sut.isSharePresented)
    }

    @Test func sharingSurfacesAFailureInsteadOfAnEmptySheet() async throws {
        let media = StubMediaRepository()
        media.error = .network
        let setup = try makeSUT(media: media)

        setup.sut.share(setup.completion)
        await setup.sut.shareTask?.value

        guard case .failed = setup.sut.share else {
            Issue.record("expected a failed share, got \(setup.sut.share)")
            return
        }
        #expect(setup.sut.isSharePresented, "the sheet is already up; it has to explain itself, not sit blank")
    }

    @Test func theQRCarriesExactlyTheURL() async throws {
        let setup = try makeSUT()

        setup.sut.share(setup.completion)
        await setup.sut.shareTask?.value

        guard case let .loaded(share) = setup.sut.share else {
            Issue.record("expected a loaded share, got \(setup.sut.share)")
            return
        }
        let detector = try #require(CIDetector(
            ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        ))
        let features = detector.features(in: CIImage(cgImage: share.qr))
        let payload = (features.first as? CIQRCodeFeature)?.messageString

        #expect(payload == share.url.absoluteString, "a scanner reads the square, not the URL we meant to encode")
    }
}
