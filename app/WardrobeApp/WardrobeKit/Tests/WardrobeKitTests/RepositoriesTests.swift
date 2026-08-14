import Foundation
import Testing
@testable import WardrobeKit

struct ActiveChallengeRepositoryTests {
    private func makeStore() throws -> UserDefaultsActiveChallengeRepository {
        let defaults = try #require(UserDefaults(suiteName: "test-\(UUID().uuidString)"))
        return UserDefaultsActiveChallengeRepository(defaults: defaults)
    }

    @Test func saveLoadClearRoundtrip() throws {
        let activeRepository = try makeStore()
        #expect(activeRepository.load() == nil)

        var challenge = ActiveChallenge(
            card: ChallengeCard(prompt: "Wear red."),
            acceptedAt: Date(timeIntervalSince1970: 1000)
        )
        challenge.photoID = UUID().uuidString
        challenge.draft.texts.append(TextItem(content: "OOTD"))
        challenge.draft.crop = CropSpec(rect: CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8))

        activeRepository.save(challenge)
        #expect(activeRepository.load() == challenge)

        activeRepository.clear()
        #expect(activeRepository.load() == nil)
    }

    @Test func hasDraftWorkReflectsPhotoAndDraft() {
        var challenge = ActiveChallenge(card: ChallengeCard(prompt: "x"), acceptedAt: .distantPast)
        #expect(!challenge.hasDraftWork)
        challenge.draft.texts = [TextItem(content: "hi")]
        #expect(challenge.hasDraftWork)
        challenge.draft.texts = []
        challenge.photoID = "abc"
        #expect(challenge.hasDraftWork)
    }
}

struct FilePhotoRepositoryTests {
    private func makeStore() -> FilePhotoRepository {
        FilePhotoRepository(directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
    }

    @Test func saveLoadDeleteRoundtrip() throws {
        let activeRepository = try makeStore()
        let data = Data([0xFF, 0xD8, 0xFF, 0x01, 0x02])

        let id = try activeRepository.saveOriginal(data)
        #expect(try activeRepository.loadOriginal(id: id) == data)

        try activeRepository.deleteOriginal(id: id)
        #expect(throws: (any Error).self) { try activeRepository.loadOriginal(id: id) }
    }

    @Test func loadMissingOrInvalidIDThrows() {
        let activeRepository = try makeStore()
        #expect(throws: (any Error).self) { try activeRepository.loadOriginal(id: UUID().uuidString) }
        #expect(throws: AppError.unexpected) { try activeRepository.loadOriginal(id: "../escape") }
    }
}
