import Foundation
import Testing
@testable import WardrobeKit

struct ActiveChallengeStoreTests {
    private func makeStore() -> UserDefaultsActiveChallengeStore {
        UserDefaultsActiveChallengeStore(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
    }

    @Test func saveLoadClearRoundtrip() {
        let store = makeStore()
        #expect(store.load() == nil)

        var challenge = ActiveChallenge(
            card: ChallengeCard(prompt: "Wear red."),
            acceptedAt: Date(timeIntervalSince1970: 1000)
        )
        challenge.photoID = UUID().uuidString
        challenge.draft.texts.append(TextItem(content: "OOTD"))
        challenge.draft.crop = CropSpec(rect: CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8))

        store.save(challenge)
        #expect(store.load() == challenge)

        store.clear()
        #expect(store.load() == nil)
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

struct FilePhotoStoreTests {
    private func makeStore() -> FilePhotoStore {
        FilePhotoStore(directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
    }

    @Test func saveLoadDeleteRoundtrip() throws {
        let store = makeStore()
        let data = Data([0xFF, 0xD8, 0xFF, 0x01, 0x02])

        let id = try store.saveOriginal(data)
        #expect(try store.loadOriginal(id: id) == data)

        try store.deleteOriginal(id: id)
        #expect(throws: (any Error).self) { try store.loadOriginal(id: id) }
    }

    @Test func loadMissingOrInvalidIDThrows() {
        let store = makeStore()
        #expect(throws: (any Error).self) { try store.loadOriginal(id: UUID().uuidString) }
        #expect(throws: AppError.unexpected) { try store.loadOriginal(id: "../escape") }
    }
}
