import Foundation
import Testing
@testable import WardrobeKit

@MainActor
struct CaptureFlowGarmentReviewTests {
    private func makeSUT(
        challenge: ActiveChallenge = ActiveChallenge(card: ChallengeCard(prompt: "x"), acceptedAt: .distantPast),
        camera: FakeCameraService = FakeCameraService(),
        activeRepository: InMemoryActiveChallengeRepository = InMemoryActiveChallengeRepository(),
        completedRepository: InMemoryCompletedChallengeRepository = InMemoryCompletedChallengeRepository(),
        photoRepository: SpyPhotoRepository = SpyPhotoRepository(),
        library: FakePhotoLibrary = FakePhotoLibrary(),
        scanner: FakeGarmentScanService = FakeGarmentScanService(),
        wardrobeRepository: InMemoryWardrobeItemRepository = InMemoryWardrobeItemRepository(),
        thumbnails: InMemoryGarmentThumbnailRepository = InMemoryGarmentThumbnailRepository()
    ) -> CaptureFlowViewModel {
        CaptureFlowViewModel(
            challenge: challenge,
            camera: camera,
            activeRepository: activeRepository,
            completedRepository: completedRepository,
            photoRepository: photoRepository,
            previews: InMemoryCompletionPreviewRepository(),
            library: library,
            scanner: scanner,
            wardrobeRepository: wardrobeRepository,
            thumbnails: thumbnails
        )
    }

    private func makeScannedGarment(decision: ScannedGarment.Decision, file: String) -> ScannedGarment {
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
            decision: decision
        )
    }

    @Test func enteringTheEditorScansThePhotoOnce() async throws {
        let photoRepository = SpyPhotoRepository()
        let photoID = try photoRepository.saveOriginal(Data([0x01]))
        var challenge = ActiveChallenge(card: ChallengeCard(prompt: "x"), acceptedAt: .distantPast)
        challenge.photoID = photoID
        let scanner = FakeGarmentScanService()
        scanner.result = [makeScannedGarment(decision: .new, file: "a.png")]
        let sut = makeSUT(challenge: challenge, photoRepository: photoRepository, scanner: scanner)

        sut.review.scanIfNeeded(photoID: sut.challenge.photoID)
        await sut.review.finishScanning()
        sut.review.scanIfNeeded(photoID: sut.challenge.photoID) // a second appearance must not rescan
        await sut.review.finishScanning()

        #expect(sut.review.garments.count == 1)
        #expect(scanner.scannedPhotos.count == 1)
    }

    @Test func aFailedScanLeavesTheEditorUsable() async {
        var challenge = ActiveChallenge(card: ChallengeCard(prompt: "x"), acceptedAt: .distantPast)
        challenge.photoID = UUID().uuidString // never saved, so loading throws
        let sut = makeSUT(challenge: challenge)

        sut.review.scanIfNeeded(photoID: sut.challenge.photoID)
        await sut.review.finishScanning()

        #expect(sut.review.garments.isEmpty)
        #expect(!sut.review.isScanning)
    }

    @Test func completingStoresConfirmedGarmentsAgainstTheCompletion() async throws {
        let photoRepository = SpyPhotoRepository()
        let photoID = try photoRepository.saveOriginal(Data([0x01]))
        var challenge = ActiveChallenge(card: ChallengeCard(prompt: "x"), acceptedAt: .distantPast)
        challenge.photoID = photoID
        let scanner = FakeGarmentScanService()
        let garment = makeScannedGarment(decision: .new, file: "a.png")
        scanner.result = [garment]
        let wardrobe = InMemoryWardrobeItemRepository()
        let completed = InMemoryCompletedChallengeRepository()
        let sut = makeSUT(
            challenge: challenge, completedRepository: completed,
            photoRepository: photoRepository, scanner: scanner, wardrobeRepository: wardrobe
        )
        sut.review.scanIfNeeded(photoID: sut.challenge.photoID)
        await sut.review.finishScanning()

        sut.completeChallenge()
        await sut.completionTask?.value

        #expect(try wardrobe.items().map(\.id) == [garment.id])
        // The wear points at the completion that produced it — the reason
        // WearRecord carries a completionID at all.
        let completionID = try #require(completed.stored.first?.id)
        #expect(try wardrobe.wears(for: garment.id).first?.completionID == completionID)
    }

    @Test func completingADuplicateAddsAWearNotAnItem() async throws {
        let photoRepository = SpyPhotoRepository()
        let photoID = try photoRepository.saveOriginal(Data([0x01]))
        var challenge = ActiveChallenge(card: ChallengeCard(prompt: "x"), acceptedAt: .distantPast)
        challenge.photoID = photoID
        let wardrobe = InMemoryWardrobeItemRepository()
        let existingID = UUID()
        try wardrobe.insert(
            WardrobeItem(id: existingID, category: .top, cutoutFile: "old.png",
                         createdAt: Date(), updatedAt: Date()),
            fingerprint: nil,
            wear: WearRecord(itemID: existingID, wornAt: Date())
        )
        let thumbnails = InMemoryGarmentThumbnailRepository()
        thumbnails.files["scanned.png"] = Data([0x01])
        let scanner = FakeGarmentScanService()
        scanner.result = [makeScannedGarment(decision: .existing(existingID), file: "scanned.png")]
        let sut = makeSUT(
            challenge: challenge, photoRepository: photoRepository,
            scanner: scanner, wardrobeRepository: wardrobe, thumbnails: thumbnails
        )
        sut.review.scanIfNeeded(photoID: sut.challenge.photoID)
        await sut.review.finishScanning()

        sut.completeChallenge()
        await sut.completionTask?.value

        #expect(try wardrobe.items().count == 1)
        #expect(try wardrobe.wears(for: existingID).count == 2)
        #expect(thumbnails.files["scanned.png"] == nil)
    }

    /// The checkmark waits for on-device work that is nearly done rather than
    /// dropping the garments it was about to produce.
    @Test func completingWhileStillScanningStillStoresTheGarments() async throws {
        let photoRepository = SpyPhotoRepository()
        let photoID = try photoRepository.saveOriginal(Data([0x01]))
        var challenge = ActiveChallenge(card: ChallengeCard(prompt: "x"), acceptedAt: .distantPast)
        challenge.photoID = photoID
        let scanner = FakeGarmentScanService()
        scanner.result = [makeScannedGarment(decision: .new, file: "a.png")]
        let wardrobe = InMemoryWardrobeItemRepository()
        let sut = makeSUT(
            challenge: challenge, photoRepository: photoRepository,
            scanner: scanner, wardrobeRepository: wardrobe
        )

        sut.review.scanIfNeeded(photoID: sut.challenge.photoID)
        sut.completeChallenge() // no await on the scan first
        await sut.completionTask?.value

        #expect(try wardrobe.items().count == 1)
        #expect(sut.isCompleted)
    }
}
