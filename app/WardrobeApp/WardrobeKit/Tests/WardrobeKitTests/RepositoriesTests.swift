import Foundation
import Testing
@testable import WardrobeKit

@MainActor
struct ActiveChallengeRepositoryTests {
    private func makeStore(
        defaults: UserDefaults? = nil
    ) throws -> FileActiveChallengeRepository {
        let directory = URL.temporaryDirectory.appending(path: "drafts-\(UUID.v7())")
        let defaults = try defaults ?? #require(UserDefaults(suiteName: "test-\(UUID.v7())"))
        return FileActiveChallengeRepository(directory: directory, legacyDefaults: defaults)
    }

    private func makeChallenge(_ text: String) -> ActiveChallenge {
        var challenge = ActiveChallenge(card: ChallengeCard(prompt: "x"), acceptedAt: .distantPast)
        challenge.document = .fixture(photoID: nil, texts: [TextItem(content: text)])
        return challenge
    }

    @Test func saveLoadClearRoundtrip() async throws {
        let activeRepository = try makeStore()
        #expect(activeRepository.load() == nil)

        var challenge = ActiveChallenge(
            card: ChallengeCard(prompt: "Wear red."),
            acceptedAt: Date(timeIntervalSince1970: 1000)
        )
        let photoID = UUID.v7()
        challenge.photoID = photoID
        challenge.document = .fixture(
            photoID: photoID,
            crop: CropSpec(rect: CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)),
            texts: [TextItem(content: "OOTD")]
        )

        activeRepository.save(challenge)
        await activeRepository.flush()
        #expect(activeRepository.load() == challenge)

        activeRepository.clear()
        await activeRepository.flush()
        #expect(activeRepository.load() == nil)
    }

    /// A save is answered from memory before the bytes land — which is what
    /// keeps reading the draft back at ✓ correct while writes are coalesced.
    @Test func aSaveIsReadableBeforeItHasBeenWritten() throws {
        let activeRepository = try makeStore()
        let challenge = makeChallenge("not on disk yet")

        activeRepository.save(challenge)

        #expect(activeRepository.load() == challenge)
    }

    /// The point of coalescing: a burst of edits is one write, and the one that
    /// lands is the last one.
    @Test func aBurstOfSavesLandsAsTheLastOne() async throws {
        let directory = URL.temporaryDirectory.appending(path: "drafts-\(UUID.v7())")
        let defaults = try #require(UserDefaults(suiteName: "test-\(UUID.v7())"))
        let activeRepository = FileActiveChallengeRepository(
            directory: directory, legacyDefaults: defaults
        )

        for index in 0 ..< 20 {
            activeRepository.save(makeChallenge("edit \(index)"))
        }
        let last = makeChallenge("edit 20")
        activeRepository.save(last)
        await activeRepository.flush()

        // Read through a second instance so the answer comes off the disk, not
        // out of the first one's memory.
        let reopened = FileActiveChallengeRepository(directory: directory, legacyDefaults: defaults)
        #expect(reopened.load() == last)
    }

    /// Updating the app must not throw away a challenge someone was in the
    /// middle of, so the old key is read once and then retired.
    @Test func aDraftLeftInTheOldStoreIsAdoptedAndTheKeyRetired() async throws {
        let directory = URL.temporaryDirectory.appending(path: "drafts-\(UUID.v7())")
        let defaults = try #require(UserDefaults(suiteName: "test-\(UUID.v7())"))
        let challenge = makeChallenge("written by the previous version")
        try defaults.set(JSONEncoder().encode(challenge), forKey: "activeChallenge")
        let activeRepository = FileActiveChallengeRepository(
            directory: directory, legacyDefaults: defaults
        )

        #expect(activeRepository.load() == challenge)
        #expect(defaults.data(forKey: "activeChallenge") == nil)
        await activeRepository.flush()

        // The same directory, so this really is reading what adoption wrote —
        // the draft now lives in the file and nowhere else.
        let reopened = FileActiveChallengeRepository(directory: directory, legacyDefaults: defaults)
        #expect(reopened.load() == challenge)
    }

    /// A write that cannot land has to say so. Before this it went to the log
    /// only, so the draft on screen and the draft on disk diverged in silence.
    @Test func aWriteThatCannotLandSaysSoAndClearsWhenOneSucceeds() async throws {
        let defaults = try #require(UserDefaults(suiteName: "test-\(UUID.v7())"))
        // A path under an existing *file*, so creating the directory fails.
        let blocker = URL.temporaryDirectory.appending(path: "blocker-\(UUID.v7())")
        try Data("not a directory".utf8).write(to: blocker)
        let unwritable = FileActiveChallengeRepository(
            directory: blocker.appending(path: "drafts"), legacyDefaults: defaults
        )

        unwritable.save(makeChallenge("nowhere to go"))
        await unwritable.flush()

        #expect(unwritable.didFailToPersist)

        let writable = FileActiveChallengeRepository(
            directory: URL.temporaryDirectory.appending(path: "drafts-\(UUID.v7())"),
            legacyDefaults: defaults
        )
        writable.save(makeChallenge("this one lands"))
        await writable.flush()

        #expect(!writable.didFailToPersist)
    }

    @Test func anUnreadableDraftFileIsNotFatal() throws {
        let directory = URL.temporaryDirectory.appending(path: "drafts-\(UUID.v7())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: directory.appending(path: "active-draft.json"))
        let defaults = try #require(UserDefaults(suiteName: "test-\(UUID.v7())"))

        let activeRepository = FileActiveChallengeRepository(
            directory: directory, legacyDefaults: defaults
        )

        #expect(activeRepository.load() == nil)
    }

    @Test func hasDraftWorkReflectsPhotoAndCanvas() {
        var challenge = ActiveChallenge(card: ChallengeCard(prompt: "x"), acceptedAt: .distantPast)
        #expect(!challenge.hasDraftWork)
        challenge.document = .fixture(photoID: nil, texts: [TextItem(content: "hi")])
        #expect(challenge.hasDraftWork)
        challenge.document = EditorDocument(layers: [])
        challenge.photoID = id("abc")
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

    /// The old spelling also asserted that `"../escape"` was refused. A `UUID`
    /// cannot spell that, so the type now carries what the runtime check did.
    @Test func loadingAnIdentityWithNoFileThrows() throws {
        let activeRepository = try makeStore()

        #expect(throws: (any Error).self) { try activeRepository.loadOriginal(id: UUID.v7()) }
    }
}
