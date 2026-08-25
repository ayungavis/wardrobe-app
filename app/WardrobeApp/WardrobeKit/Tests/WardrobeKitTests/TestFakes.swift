@preconcurrency import AVFoundation
import CryptoKit
import Foundation
@testable import WardrobeKit

final class InMemoryActiveChallengeRepository: ActiveChallengeRepository, @unchecked Sendable {
    var stored: ActiveChallenge?
    /// Counted, not just recorded: an edit the document refused must not reach
    /// the store at all, and only a count can tell that apart from a write that
    /// happened to store the same value.
    private(set) var saveCount = 0

    func load() -> ActiveChallenge? {
        stored
    }

    func save(_ challenge: ActiveChallenge) {
        stored = challenge
        saveCount += 1
    }

    func clear() {
        stored = nil
    }

    /// Nothing is ever in flight here, so there is nothing to wait for and
    /// nothing that can fail.
    func flush() async {}
    var didFailToPersist: Bool {
        false
    }
}

final class InMemoryCompletedChallengeRepository: CompletedChallengeRepository, @unchecked Sendable {
    var stored: [CompletedChallenge] = []

    func load() -> [CompletedChallenge] {
        stored
    }

    func append(_ completion: CompletedChallenge) {
        guard !hasCompletion(on: completion.completedAt) else { return }
        stored.append(completion)
    }

    func removeCompletions(on date: Date) {
        stored.removeAll { Calendar.current.isDate($0.completedAt, inSameDayAs: date) }
    }

    @discardableResult
    func stageStatus(id: UUID, status: CompletionStatus) -> Bool {
        guard let index = stored.firstIndex(where: { $0.id == id }) else { return false }
        stored[index].status = status
        return true
    }

    func commitStaged() {}

    func removeAll() {
        stored = []
    }
}

@MainActor
final class InMemoryWardrobeItemRepository: WardrobeItemRepository {
    var storedItems: [WardrobeItem] = []
    var storedFingerprints: [ItemFingerprint] = []
    var storedWears: [WearRecord] = []
    var storedConflicts: [ItemConflict] = []
    var itemsError: Error?

    func items() throws -> [WardrobeItem] {
        if let itemsError {
            throw itemsError
        }
        return storedItems.sorted { $0.createdAt > $1.createdAt }
    }

    func fingerprints() throws -> [ItemFingerprint] {
        storedFingerprints
    }

    func wears(for itemID: UUID) throws -> [WearRecord] {
        storedWears.filter { $0.itemID == itemID }
    }

    func openConflicts() throws -> [ItemConflict] {
        storedConflicts.filter { $0.resolvedAt == nil }
    }

    func resolveConflict(_ conflict: ItemConflict, choosing choice: ConflictChoice) throws {
        let index = storedItems.firstIndex { $0.id == conflict.itemID }
        if choice == .useIncoming, conflict.field == .name, let value = conflict.value, let index {
            storedItems[index].name = value
        }
        storedConflicts = storedConflicts.map { row in
            guard row.itemID == conflict.itemID, row.field == conflict.field else { return row }
            return ItemConflict(
                id: row.id, itemID: row.itemID, field: row.field,
                value: row.value, revision: row.revision, resolvedAt: Date()
            )
        }
    }

    func update(_ item: WardrobeItem) throws {
        guard let index = storedItems.firstIndex(where: { $0.id == item.id }) else { return }
        storedItems[index] = item
    }

    func insert(_ item: WardrobeItem, fingerprint: ItemFingerprint?, wear: WearRecord?) throws {
        storedItems.append(item)
        if let fingerprint {
            storedFingerprints.append(fingerprint)
        }
        if let wear {
            storedWears.append(wear)
        }
    }

    func stageInsert(_ item: WardrobeItem, fingerprint: ItemFingerprint?, wear: WearRecord?) {
        try? insert(item, fingerprint: fingerprint, wear: wear)
    }

    func stageWear(_ wear: WearRecord?, fingerprint: ItemFingerprint) {
        try? recordWear(wear, fingerprint: fingerprint)
    }

    func commitStaged() throws {}

    func discardStaged() {}

    func recordWear(_ wear: WearRecord?, fingerprint: ItemFingerprint) throws {
        if let wear {
            storedWears.append(wear)
        }
        storedFingerprints.append(fingerprint)
    }

    func delete(itemID: UUID) throws {
        storedItems.removeAll { $0.id == itemID }
        storedFingerprints.removeAll { $0.itemID == itemID }
        storedWears.removeAll { $0.itemID == itemID }
    }

    func deleteAll() throws {
        storedItems.removeAll()
        storedFingerprints.removeAll()
        storedWears.removeAll()
    }
}

@MainActor
final class FakeGarmentScanService: GarmentScanService {
    var result: [ScannedGarment] = []
    var error: Error?
    private(set) var scannedPhotos: [Data] = []

    func scan(photo: Data) async throws -> [ScannedGarment] {
        scannedPhotos.append(photo)
        if let error {
            throw error
        }
        return result
    }
}

/// An actor, mirroring the real browser's isolation, so tests exercise the
/// same async boundaries.
actor FakePhotoLibrary: PhotoLibraryService {
    private var currentAccess: PhotoLibraryAccess
    private var accessAfterRequest: PhotoLibraryAccess
    private var assets: [PhotoAsset]
    private var thumbnailImage: CGImage?
    private var data: Data?
    private(set) var requestAccessCount = 0

    init(
        access: PhotoLibraryAccess = .notDetermined,
        accessAfterRequest: PhotoLibraryAccess = .authorized,
        assets: [PhotoAsset] = [],
        thumbnail: CGImage? = nil,
        data: Data? = nil
    ) {
        currentAccess = access
        self.accessAfterRequest = accessAfterRequest
        self.assets = assets
        thumbnailImage = thumbnail
        self.data = data
    }

    func access() async -> PhotoLibraryAccess {
        currentAccess
    }

    func requestAccess() async -> PhotoLibraryAccess {
        requestAccessCount += 1
        currentAccess = accessAfterRequest
        return currentAccess
    }

    func recentAssets(limit: Int) async -> [PhotoAsset] {
        currentAccess.canBrowse ? Array(assets.prefix(limit)) : []
    }

    func thumbnail(for _: String, maxPixel _: CGFloat) async -> CGImage? {
        thumbnailImage
    }

    func imageData(for _: String) async -> Data? {
        data
    }
}

final class SpyPhotoRepository: PhotoRepository, @unchecked Sendable {
    var saved: [UUID: Data] = [:]
    var deleted: [UUID] = []
    var saveError: Error?

    func saveOriginal(_ data: Data) throws -> UUID {
        if let saveError {
            throw saveError
        }
        let id = UUID.v7()
        saved[id] = data
        return id
    }

    func saveOriginal(_ data: Data, id: UUID) throws {
        if let saveError {
            throw saveError
        }
        saved[id] = data
    }

    func hasOriginal(id: UUID) -> Bool {
        saved[id] != nil
    }

    func loadOriginal(id: UUID) throws -> Data {
        guard let data = saved[id] else { throw AppError.unexpected }
        return data
    }

    func deleteOriginal(id: UUID) throws {
        deleted.append(id)
        saved[id] = nil
    }
}

final class InMemoryAccountPreferencesRepository: AccountPreferencesRepository, @unchecked Sendable {
    // @unchecked: tests drive it from one actor at a time.
    var stored = AccountPreferences()

    func load() -> AccountPreferences {
        stored
    }

    func save(_ preferences: AccountPreferences) {
        stored = preferences
    }

    func applyRemote(_ preferences: AccountPreferences) {
        stored = preferences
    }
}

// -------------------------------------------------- readable photo identities

/// A stable UUID for a fixture name, so `id("photo-1")` still reads like the
/// string literal it replaced while satisfying the typed identity.
let samplePhotoID = id("photo-1")

func id(_ name: String) -> UUID {
    var bytes = Array(SHA256.hash(data: Data(name.utf8)).prefix(16))
    bytes[6] = (bytes[6] & 0x0F) | 0x70
    bytes[8] = (bytes[8] & 0x3F) | 0x80
    return UUID(uuid: (
        bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
        bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
    ))
}
