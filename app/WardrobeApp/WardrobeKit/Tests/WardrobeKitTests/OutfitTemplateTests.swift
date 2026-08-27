import Foundation
import Testing
@testable import WardrobeKit

@MainActor
final class TemplateRequestSpy: @unchecked Sendable {
    // Type safety: written and read only from the main actor in these tests.
    private(set) nonisolated(unsafe) var requests: [TemplateRequest] = []
    nonisolated(unsafe) var answer: UUID = .v7()

    nonisolated func send(_ request: TemplateRequest) async throws -> UUID {
        requests.append(request)
        return answer
    }
}

@MainActor
final class PullSpy {
    private(set) var count = 0
    var onPull: (() -> Void)?

    func pull() {
        count += 1
        onPull?()
    }
}

@MainActor
struct OutfitTemplateTests {
    private struct Setup {
        let sut: EditorViewModel
        let spy: TemplateRequestSpy
        let photos: SpyPhotoRepository
        let review: GarmentReviewModel
    }

    private func makeSUT(
        consentNeeded: Bool = false,
        scanned: [String] = [],
        discarded: String? = nil,
        syncNow: (() async -> Void)? = nil
    ) throws -> Setup {
        let photos = SpyPhotoRepository()
        let photoID = try photos.saveOriginal(Data([0xAA]))
        var challenge = ActiveChallenge(card: ChallengeCard(prompt: "x"), acceptedAt: Date())
        challenge.photoID = photoID
        challenge.document = .fixture(
            photoID: photoID,
            texts: [TextItem(content: "hello", position: .zero)],
            stickers: [StickerItem(emoji: "✨", position: .zero)]
        )
        let spy = TemplateRequestSpy()
        let thumbnails = InMemoryGarmentThumbnailRepository()
        let review = GarmentReviewModel(
            scanner: FakeGarmentScanService(),
            photoRepository: photos,
            wardrobeRepository: InMemoryWardrobeItemRepository(),
            thumbnails: thumbnails
        )
        for file in scanned {
            thumbnails.files[file] = Data([0xEE])
        }
        review.stage(scanned.map { file in
            let id = UUID()
            return ScannedGarment(
                id: id, category: .top, cutoutFile: file,
                fingerprint: ItemFingerprint(
                    itemID: id, version: "v1", colorLab: [70, 5, 15], aspectRatio: 0.8,
                    featurePrint: Data([1, 2, 3, 4]), maskQuality: 1, createdAt: Date()
                ),
                matches: [], decision: file == discarded ? .discard : .new
            )
        })

        let sut = EditorViewModel(
            challenge: challenge,
            activeRepository: InMemoryActiveChallengeRepository(),
            photoRepository: photos,
            librarySaver: SpyPhotoLibrarySaver(),
            preferencesRepository: InMemoryAccountPreferencesRepository(),
            wardrobeRepository: InMemoryWardrobeItemRepository(),
            thumbnails: thumbnails,
            requestTemplate: { try await spy.send($0) },
            review: review,
            needsUploadConsent: consentNeeded,
            sleep: { _ in },
            syncNow: syncNow
        )
        return Setup(sut: sut, spy: spy, photos: photos, review: review)
    }

    @Test func choosingATemplateHandsTheContainerThePhoto() async throws {
        let setup = try makeSUT()

        setup.sut.chooseTemplate(.blisterGreen)
        await setup.sut.templateTask?.value

        #expect(setup.spy.requests.count == 1)
        #expect(setup.spy.requests.first?.template == .blisterGreen)
        #expect(setup.spy.requests.first?.photo == Data([0xAA]))
    }

    @Test func aMissingConsentAsksForItInsteadOfSendingAnything() async throws {
        let setup = try makeSUT(consentNeeded: true)

        setup.sut.chooseTemplate(.lookbook)
        await setup.sut.templateTask?.value

        #expect(setup.sut.isConsentPresented)
        #expect(setup.spy.requests.isEmpty, "nothing may leave the device before consent")
    }

    @Test func theTemplateCarriesTheGarmentsFromTheReviewNotTheCanvas() async throws {
        let setup = try makeSUT(scanned: ["a.png", "b.png"])

        setup.sut.chooseTemplate(.lookbook)
        await setup.sut.templateTask?.value

        #expect(
            setup.spy.requests.first?.garments.count == 2,
            "the page lists what was scanned, not what happens to be stuck on the canvas"
        )
    }

    @Test func garmentsTheUserDiscardedAreLeftOut() async throws {
        let setup = try makeSUT(scanned: ["a.png", "b.png"], discarded: "b.png")

        setup.sut.chooseTemplate(.lookbook)
        await setup.sut.templateTask?.value

        #expect(setup.spy.requests.first?.garments.count == 1)
    }

    @Test func theBannerHasSomethingToShowFromTheMomentItIsTapped() throws {
        let setup = try makeSUT()

        setup.sut.chooseTemplate(.lookbook)

        #expect(setup.sut.isMakingTemplate, "waiting starts at the tap, not when the network answers")
        #expect(setup.sut.templateState == .loading)
    }

    @Test func cancellingStopsTheWaitAndClearsTheBanner() async throws {
        let setup = try makeSUT()
        setup.sut.chooseTemplate(.lookbook)

        setup.sut.cancelTemplate()
        await setup.sut.templateTask?.value

        #expect(!setup.sut.isMakingTemplate)
        #expect(setup.sut.pendingTemplateID == nil)
    }

    @Test func retryingAsksForTheSameStyleAgain() async throws {
        let setup = try makeSUT()
        setup.sut.chooseTemplate(.blisterCream)
        await setup.sut.templateTask?.value

        setup.sut.retryTemplate()
        await setup.sut.templateTask?.value

        #expect(setup.spy.requests.map(\.template) == [.blisterCream, .blisterCream])
    }

    @Test func aTemplateThatNeverArrivesEndsAsAFailureRatherThanWaitingForever() async throws {
        let setup = try makeSUT()

        setup.sut.chooseTemplate(.lookbook)
        await setup.sut.templateTask?.value

        guard case .failed = setup.sut.templateState else {
            Issue.record("expected a failure, got \(setup.sut.templateState)")
            return
        }
        #expect(setup.sut.templateTimedOut, "the job may still be running; say so instead of claiming failure")
    }

    @Test func theArrivingTemplateLandsAsAPageLayerJustAboveTheChallengePhoto() throws {
        let setup = try makeSUT()
        let before = setup.sut.document.layers
        #expect(before.count >= 3, "an empty document would make the ordering assertions vacuous")
        let background = setup.sut.document.background
        let request = UUID.v7()
        setup.sut.pendingTemplateID = request
        setup.sut.templateState = .loading
        try setup.photos.saveOriginal(Data([0xBB, 0xCC]), id: request)

        setup.sut.adoptTemplateIfArrived()

        let layers = setup.sut.document.layers
        #expect(layers.count == before.count + 1, "the page is a layer of its own, not a replacement")
        guard let photoIndex = layers.firstIndex(where: { $0.id == setup.sut.challengePhotoLayerID }),
              layers.indices.contains(photoIndex + 1)
        else {
            Issue.record("expected a layer above the challenge photo")
            return
        }
        guard case let .photo(page) = layers[photoIndex + 1].content else {
            Issue.record("expected a photo layer, got \(layers[photoIndex + 1].content)")
            return
        }
        #expect(page.style == .page, "a polaroid well is 3:4 and would crop the 9:16 page")
        #expect(
            Set(before.map(\.id)).isSubset(of: Set(layers.map(\.id))),
            "a layer the user placed must not be traded for the page"
        )
        #expect(setup.sut.document.background == background, "the page is a layer now, not the ground")
    }

    @Test func theArrivingPageStaysUnderTheStickersTheUserPlaced() throws {
        let setup = try makeSUT()
        let placed = setup.sut.document.layers.filter { layer in
            if case .photo = layer.content {
                return false
            }
            return true
        }
        #expect(!placed.isEmpty, "this test needs something placed on top to be about anything")
        let request = UUID.v7()
        setup.sut.pendingTemplateID = request
        setup.sut.templateState = .loading
        try setup.photos.saveOriginal(Data([0xBB, 0xCC]), id: request)

        setup.sut.adoptTemplateIfArrived()

        let layers = setup.sut.document.layers
        guard let pageIndex = layers.firstIndex(where: { layer in
            if case let .photo(photo) = layer.content {
                return photo.style == .page
            }
            return false
        }) else {
            Issue.record("expected a page layer")
            return
        }
        for layer in placed {
            guard let index = layers.firstIndex(where: { $0.id == layer.id }) else {
                Issue.record("a placed layer went missing")
                return
            }
            #expect(index > pageIndex, "the page must not bury what the user already stuck down")
        }
    }

    @Test func theWaitPullsTheFeedOnEveryTick() async throws {
        let pull = PullSpy()
        let setup = try makeSUT(syncNow: { pull.pull() })
        let request = setup.spy.answer
        pull.onPull = { [photos = setup.photos] in
            guard pull.count == 3 else { return }
            try? photos.saveOriginal(Data([0xBB, 0xCC]), id: request)
        }

        setup.sut.chooseTemplate(.lookbook)
        await setup.sut.templateTask?.value

        #expect(pull.count == 3, "the page only lands because the wait pulls the feed each tick")
        #expect(setup.sut.templateState == .idle)
        #expect(setup.sut.document.layers.contains { layer in
            if case let .photo(photo) = layer.content {
                return photo.style == .page
            }
            return false
        }, "the pull is only worth anything if the page it fetches reaches the canvas")
    }

    @Test func retryingAdoptsAPageThatArrivedAfterTheTimeoutInsteadOfAskingAgain() async throws {
        let setup = try makeSUT()
        setup.sut.chooseTemplate(.lookbook)
        await setup.sut.templateTask?.value
        #expect(setup.sut.templateTimedOut, "this test is about what happens after the wait gives up")
        try setup.photos.saveOriginal(Data([0xBB, 0xCC]), id: setup.spy.answer)

        setup.sut.retryTemplate()
        await setup.sut.templateTask?.value

        #expect(setup.spy.requests.count == 1, "the page is already here; asking again burns the quota")
        #expect(setup.sut.templateState == .idle)
        #expect(!setup.sut.templateTimedOut)
    }
}
