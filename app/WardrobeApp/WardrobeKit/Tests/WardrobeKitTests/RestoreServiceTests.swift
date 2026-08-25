import Foundation
import SwiftData
import Testing
@testable import WardrobeKit

@MainActor
struct RestoreServiceTests {
    // MARK: - Idempotence, which is what lets a page retry

    @Test func applyingTheSamePageTwiceDuplicatesNothing() throws {
        let sut = try makeSUT()
        let page = try page([itemJSON(), fingerprintJSON(), wearJSON()])

        try sut.applier.apply(page)
        try sut.repository.commitStaged()
        try sut.applier.apply(page)
        try sut.repository.commitStaged()

        #expect(try sut.repository.items().count == 1)
        #expect(try sut.repository.fingerprints().count == 1)
        #expect(try sut.repository.wears(for: itemID).count == 1)
    }

    // MARK: - Semantics per kind

    @Test func aPulledTombstoneBuriesTheLocalItemAndItsFingerprint() throws {
        let sut = try makeSUT()
        try sut.applier.apply(page([itemJSON(), fingerprintJSON()]))
        try sut.repository.commitStaged()
        #expect(try sut.repository.items().count == 1)

        try sut.applier.apply(page([itemJSON(deleted: true)]))
        try sut.repository.commitStaged()

        #expect(try sut.repository.items().isEmpty)
        #expect(try sut.repository.fingerprints().isEmpty, "a buried item stops matching")
    }

    @Test func aPulledEditUpdatesInPlace() throws {
        let sut = try makeSUT()
        try sut.applier.apply(page([itemJSON(name: "coat")]))
        try sut.repository.commitStaged()

        try sut.applier.apply(page([itemJSON(name: "storm coat")]))
        try sut.repository.commitStaged()

        let items = try sut.repository.items()
        #expect(items.count == 1)
        #expect(items.first?.name == "storm coat")
    }

    @Test func anExistingFingerprintVersionIsNeverOverwritten() throws {
        let sut = try makeSUT()
        try sut.applier.apply(page([fingerprintJSON(version: "v1")]))
        try sut.repository.commitStaged()

        try sut.applier.apply(page([fingerprintJSON(version: "v2")]))
        try sut.repository.commitStaged()

        let versions = try sut.repository.fingerprints().map(\.version)
        #expect(versions == ["v1"], "FR-063: immutable versions, union by id")
    }

    @Test func consentLandsSoASecondDeviceDoesNotReAsk() throws {
        let sut = try makeSUT()
        #expect(sut.preferences.load().uploadConsentAt == nil)

        try sut.applier.apply(page([preferenceJSON()]))

        #expect(sut.preferences.load().uploadConsentAt != nil)
        #expect(sut.preferences.enqueuedCount == 0, "a pulled value must not echo back as a mutation")
    }

    @Test func skippedKindsDoNotStopTheirNeighbours() throws {
        let sut = try makeSUT()
        let mixed = try page([completionJSON(), itemJSON(), conflictJSON()])

        try sut.applier.apply(mixed)
        try sut.repository.commitStaged()

        #expect(try sut.repository.items().count == 1)
    }

    // MARK: - Fixtures

    private let itemID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, 0x0A))
    private let fingerprintID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, 0x0B))
    private let wearID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, 0x0C))

    private struct SUT {
        let applier: LocalRestoreService
        let repository: SwiftDataWardrobeItemRepository
        let preferences: CountingPreferencesRepository
    }

    private func makeSUT() throws -> SUT {
        let container = try ModelContainer(
            for: SwiftDataWardrobeItemRepository.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let repository = SwiftDataWardrobeItemRepository(context: ModelContext(container))
        let preferences = CountingPreferencesRepository()
        return SUT(
            applier: LocalRestoreService(wardrobe: repository, preferences: preferences),
            repository: repository,
            preferences: preferences
        )
    }

    private func page(_ records: [String]) throws -> [ChangeDTO] {
        let entries = records.enumerated().map { index, record in
            "{\"changeSeq\":\(index + 1),\(record)}"
        }
        let json = "{\"changes\":[\(entries.joined(separator: ","))],\"nextSince\":\(records.count)}"
        return try JSONDecoder.api.decode(GetChangesResponseDTO.self, from: Data(json.utf8)).changes
    }

    private func itemJSON(name: String = "coat", deleted: Bool = false) -> String {
        let deletedAt = deleted ? "\"2026-08-25T12:00:00Z\"" : "null"
        return #"""
        "kind":"wardrobeItem","record":{"id":"\#(itemID)","category":"top","name":"\#(name)",
         "color":null,"garmentType":null,"description":null,
         "attributeRevisions":{"name":{"rev":3}},"illustrationState":"none",
         "currentIllustrationId":null,"changeSeq":1,"deletedAt":\#(deletedAt)}
        """#
    }

    private func fingerprintJSON(version: String = "v1") -> String {
        #"""
        "kind":"itemFingerprint","record":{"id":"\#(fingerprintID)","itemId":"\#(itemID)",
         "version":"\#(version)","colorLab":[1,2,3],"aspectRatio":0.75,"featurePrint":"AP8=",
         "maskQuality":0.9,"sourcePhotoId":null,"changeSeq":1,"deletedAt":null}
        """#
    }

    private func wearJSON() -> String {
        #"""
        "kind":"wearRecord","record":{"id":"\#(wearID)","itemId":"\#(itemID)","wornOn":"2026-08-25",
         "revision":1,"completionId":null,"sourcePhotoId":null,"changeSeq":1,"deletedAt":null}
        """#
    }

    private func preferenceJSON() -> String {
        #"""
        "kind":"accountPreference","record":{"recentStickerIds":["a"],"lastTextStyle":{},
         "onboardingCompletedAt":null,"uploadConsentAt":"2026-08-25T09:00:00Z",
         "changeSeq":1,"deletedAt":null}
        """#
    }

    private func completionJSON() -> String {
        #"""
        "kind":"challengeCompletion","record":{"id":"\#(UUID())","cardId":"\#(UUID())",
         "status":"canonical","localDate":"2026-08-25","timeZone":"Asia/Makassar",
         "completedAt":"2026-08-25T09:00:00Z","photoId":null,"currentDerivativeId":null,
         "changeSeq":1,"deletedAt":null}
        """#
    }

    private func conflictJSON() -> String {
        #"""
        "kind":"wardrobeItemConflict","record":{"id":"\#(UUID())","itemId":"\#(itemID)",
         "field":"name","value":"x","revision":1,"originDevice":null,"resolvedAt":null,"changeSeq":1}
        """#
    }
}

// MARK: - Doubles

@MainActor
final class CountingPreferencesRepository: AccountPreferencesRepository {
    private var stored = AccountPreferences()
    private(set) var enqueuedCount = 0

    func load() -> AccountPreferences {
        stored
    }

    func save(_ preferences: AccountPreferences) {
        if preferences.syncable != stored.syncable {
            enqueuedCount += 1
        }
        stored = preferences
    }

    func applyRemote(_ preferences: AccountPreferences) {
        stored = preferences
    }
}
