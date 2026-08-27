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
struct OutfitTemplateTests {
    private struct Setup {
        let sut: EditorViewModel
        let spy: TemplateRequestSpy
        let photos: SpyPhotoRepository
    }

    private func makeSUT(consentNeeded: Bool = false) throws -> Setup {
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

        let sut = EditorViewModel(
            challenge: challenge,
            activeRepository: InMemoryActiveChallengeRepository(),
            photoRepository: photos,
            librarySaver: SpyPhotoLibrarySaver(),
            preferencesRepository: InMemoryAccountPreferencesRepository(),
            wardrobeRepository: InMemoryWardrobeItemRepository(),
            thumbnails: InMemoryGarmentThumbnailRepository(),
            requestTemplate: { try await spy.send($0) },
            needsUploadConsent: consentNeeded,
            sleep: { _ in }
        )
        return Setup(sut: sut, spy: spy, photos: photos)
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

    @Test func theArrivingTemplateBecomesTheBackgroundAndKeepsEveryLayer() throws {
        let setup = try makeSUT()
        let before = setup.sut.document.layers
        #expect(before.count >= 2, "an empty document would make the layer assertion below vacuous")
        let request = UUID.v7()
        setup.sut.pendingTemplateID = request
        setup.sut.templateState = .loading
        try setup.photos.saveOriginal(Data([0xBB, 0xCC]), id: request)

        setup.sut.adoptTemplateIfArrived()

        guard case .photo = setup.sut.document.background else {
            Issue.record("expected a photo background, got \(setup.sut.document.background)")
            return
        }
        #expect(
            setup.sut.document.layers.map(\.id) == before.map(\.id),
            "the page goes underneath; a layer the user placed must not be traded for it"
        )
    }
}
