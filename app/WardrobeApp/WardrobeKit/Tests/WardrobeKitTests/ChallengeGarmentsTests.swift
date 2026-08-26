import Foundation
import Testing
@testable import WardrobeKit

@MainActor
struct ChallengeGarmentsTests {
    private func item(illustration: UUID?, cutout: Data?, name: String) -> (WardrobeItem, Data?) {
        let id = UUID()
        let item = WardrobeItem(
            id: id,
            name: name,
            category: .top,
            cutoutFile: "\(id.uuidString)-cutout.png",
            currentIllustrationID: illustration,
            createdAt: Date(),
            updatedAt: Date()
        )
        return (item, cutout)
    }

    private func makeSUT(
        cards: [ChallengeCard],
        items: [WardrobeItem],
        files: [String: Data]
    ) async -> ChallengeViewModel {
        let wardrobe = InMemoryWardrobeItemRepository()
        wardrobe.storedItems = items
        let thumbnails = InMemoryGarmentThumbnailRepository()
        thumbnails.files = files
        let repository = ControlledChallengeRepository()
        let sut = ChallengeViewModel(
            challengeRepository: repository,
            activeRepository: InMemoryActiveChallengeRepository(),
            completedRepository: InMemoryCompletedChallengeRepository(),
            photoRepository: SpyPhotoRepository(),
            wardrobeRepository: wardrobe,
            thumbnails: thumbnails
        )
        sut.load()
        await repository.resolveNext(cards: cards)
        await sut.loadTask?.value
        return sut
    }

    @Test func aCardPrefersTheIllustrationOverTheCutout() async {
        let illustration = UUID()
        let (top, _) = item(illustration: illustration, cutout: nil, name: "White tee")
        let (bottom, _) = item(illustration: nil, cutout: nil, name: "Blue jeans")
        let card = ChallengeCard(prompt: "Mix", topItemID: top.id, bottomItemID: bottom.id)
        let sut = await makeSUT(
            cards: [card],
            items: [top, bottom],
            files: [
                "\(illustration.uuidString).png": Data([0xAA]),
                top.cutoutFile: Data([0xBB]),
                bottom.cutoutFile: Data([0xCC]),
            ]
        )

        let garments = sut.garments(for: card)

        #expect(garments.top?.data == Data([0xAA]), "the drawn sticker wins over the raw cut-out")
        #expect(garments.top?.name == "White tee")
        #expect(garments.bottom?.data == Data([0xCC]), "no illustration yet falls back to the cut-out")
    }

    @Test func anUnknownItemYieldsNoGarmentRatherThanAPlaceholder() async {
        let card = ChallengeCard(prompt: "Mix", topItemID: UUID(), bottomItemID: UUID())
        let sut = await makeSUT(cards: [card], items: [], files: [:])

        let garments = sut.garments(for: card)

        #expect(garments.isEmpty,
                "FR-008 forbids an empty image container; the card simply reads as text")
    }

    @Test func aTextOnlyCardResolvesNothing() async {
        let card = ChallengeCard(prompt: "Wear red")
        let sut = await makeSUT(cards: [card], items: [], files: [:])

        #expect(sut.garments(for: card).isEmpty)
    }
}
