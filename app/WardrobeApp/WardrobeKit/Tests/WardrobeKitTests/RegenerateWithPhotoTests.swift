import Foundation
import SwiftData
import Testing
@testable import WardrobeKit

@MainActor
struct RegenerateWithPhotoTests {
    private struct Setup {
        let sut: WardrobeItemDetailViewModel
        let outbox: StoredOutboxRepository
        let uploads: StoredMediaUploadRepository
        let thumbnails: InMemoryGarmentThumbnailRepository
        let scanner: FakeGarmentScanService
        let itemID: UUID
    }

    private func makeSUT(found: [String] = ["fresh.png"]) async throws -> Setup {
        let container = try ModelContainer(
            for: SwiftDataWardrobeItemRepository.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let outbox = StoredOutboxRepository(store: SwiftDataOutboxStore(context: context))
        let repository = SwiftDataWardrobeItemRepository(context: context, outbox: outbox)

        let itemID = UUID()
        try repository.insert(
            WardrobeItem(
                id: itemID, category: .top, cutoutFile: "old.png",
                createdAt: Date(), updatedAt: Date()
            ),
            fingerprint: nil,
            wear: nil
        )
        try outbox.removeAll()

        let thumbnails = InMemoryGarmentThumbnailRepository()
        thumbnails.files["old.png"] = Data([0x01])
        let scanner = FakeGarmentScanService()
        scanner.result = found.map { file in
            thumbnails.files[file] = Data([0x02])
            return makeGarment(file: file)
        }
        let uploads = makeInMemoryUploads()

        let sut = WardrobeItemDetailViewModel(
            itemID: itemID, repository: repository, thumbnails: thumbnails,
            scanner: scanner, uploads: uploads
        )
        sut.load()
        await sut.loadTask?.value
        return Setup(
            sut: sut, outbox: outbox, uploads: uploads, thumbnails: thumbnails,
            scanner: scanner, itemID: itemID
        )
    }

    private func makeGarment(file: String) -> ScannedGarment {
        let id = UUID()
        return ScannedGarment(
            id: id,
            category: .top,
            cutoutFile: file,
            fingerprint: ItemFingerprint(
                itemID: id, version: "v1", colorLab: [70, 5, 15], aspectRatio: 0.8,
                featurePrint: Data([1, 2, 3, 4]), maskQuality: 1, createdAt: Date()
            ),
            matches: [],
            decision: .new
        )
    }

    @Test func anItemThatNeverCameFromAChallengeHasNoOriginalPhoto() async throws {
        let setup = try await makeSUT()

        #expect(
            setup.sut.originalPhotoData() == nil,
            "wardrobe-camera items carry no wear at all and imported ones carry no completion id"
        )
    }

    @Test func theChosenCutoutIsStagedBeforeTheRegenerateRequest() async throws {
        let setup = try await makeSUT()
        setup.sut.scanReferencePhoto(Data([0xAA]))
        await setup.sut.scanTask?.value

        setup.sut.regenerateIllustration(note: "linen")

        let staged = try setup.outbox.entries().map(\.name)
        #expect(
            staged == ["upsertItem", "regenerateIllustration"],
            "the new cut-out has to be recorded before the job that reads it is asked for"
        )
    }

    @Test func theCutoutBytesAreQueuedForUpload() async throws {
        let setup = try await makeSUT()
        setup.sut.scanReferencePhoto(Data([0xAA]))
        await setup.sut.scanTask?.value

        setup.sut.regenerateIllustration(note: "")

        let queued = try setup.uploads.entries()
        #expect(queued.count == 1)
        #expect(queued.first?.kind == .cutout)
        #expect(queued.first?.source == .thumbnailFile("fresh.png"), "an id with no bytes behind it never renders")
    }

    @Test func theItemAdoptsTheChosenCutout() async throws {
        let setup = try await makeSUT()
        setup.sut.scanReferencePhoto(Data([0xAA]))
        await setup.sut.scanTask?.value

        setup.sut.regenerateIllustration(note: "")
        setup.sut.load()
        await setup.sut.loadTask?.value

        #expect(setup.sut.item?.cutoutFile == "fresh.png")
    }

    @Test func cancellingDeletesTheCutoutsNobodyChose() async throws {
        let setup = try await makeSUT(found: ["a.png", "b.png"])
        setup.sut.scanReferencePhoto(Data([0xAA]))
        await setup.sut.scanTask?.value
        #expect(setup.sut.chosenCandidateID == nil, "two garments is a question, not a default")

        setup.sut.discardCandidates()

        #expect(setup.thumbnails.files["a.png"] == nil)
        #expect(setup.thumbnails.files["b.png"] == nil, "an unreferenced cut-out on disk is a leak")
    }

    @Test func regeneratingWithoutAPhotoQueuesNothingElse() async throws {
        let setup = try await makeSUT()

        setup.sut.regenerateIllustration(note: "linen")

        #expect(try setup.outbox.entries().map(\.name) == ["regenerateIllustration"])
        #expect(try setup.uploads.entries().isEmpty)
        #expect(setup.sut.item?.cutoutFile == "old.png", "the old path stays untouched when no photo was attached")
    }
}
