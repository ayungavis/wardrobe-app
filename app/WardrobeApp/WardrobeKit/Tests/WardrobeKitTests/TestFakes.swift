@preconcurrency import AVFoundation
import Foundation
@testable import WardrobeKit

final class InMemoryActiveChallengeRepository: ActiveChallengeRepository, @unchecked Sendable {
    var stored: ActiveChallenge?

    func load() -> ActiveChallenge? {
        stored
    }

    func save(_ challenge: ActiveChallenge) {
        stored = challenge
    }

    func clear() {
        stored = nil
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
}

@MainActor
final class InMemoryWardrobeItemRepository: WardrobeItemRepository {
    var storedItems: [WardrobeItem] = []
    var storedFingerprints: [ItemFingerprint] = []
    var storedWears: [WearRecord] = []

    func items() throws -> [WardrobeItem] {
        storedItems.sorted { $0.createdAt > $1.createdAt }
    }

    func fingerprints() throws -> [ItemFingerprint] {
        storedFingerprints
    }

    func wears(for itemID: UUID) throws -> [WearRecord] {
        storedWears.filter { $0.itemID == itemID }
    }

    func insert(_ item: WardrobeItem, fingerprint: ItemFingerprint?, wear: WearRecord) throws {
        storedItems.append(item)
        if let fingerprint {
            storedFingerprints.append(fingerprint)
        }
        storedWears.append(wear)
    }

    func recordWear(_ wear: WearRecord, fingerprint: ItemFingerprint) throws {
        storedWears.append(wear)
        storedFingerprints.append(fingerprint)
    }

    func deleteAll() throws {
        storedItems.removeAll()
        storedFingerprints.removeAll()
        storedWears.removeAll()
    }
}

final class InMemoryGarmentThumbnailRepository: GarmentThumbnailRepository, @unchecked Sendable {
    var files: [String: Data] = [:]
    private(set) var deleteAllCount = 0

    func save(_: CGImage, id: UUID) throws -> String {
        let file = "\(id.uuidString).png"
        files[file] = Data([0x01])
        return file
    }

    func data(forFile file: String) throws -> Data {
        guard let data = files[URL(filePath: file).lastPathComponent] else { throw AppError.unexpected }
        return data
    }

    func delete(file: String) throws {
        files[URL(filePath: file).lastPathComponent] = nil
    }

    func deleteAll() throws {
        deleteAllCount += 1
        files.removeAll()
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
    var saved: [String: Data] = [:]
    var deleted: [String] = []
    var saveError: Error?

    func saveOriginal(_ data: Data) throws -> String {
        if let saveError {
            throw saveError
        }
        let id = UUID().uuidString
        saved[id] = data
        return id
    }

    func loadOriginal(id: String) throws -> Data {
        guard let data = saved[id] else { throw AppError.unexpected }
        return data
    }

    func deleteOriginal(id: String) throws {
        deleted.append(id)
        saved[id] = nil
    }
}

@MainActor
final class FakeCameraService: CameraService {
    var permission: CameraPermission = .notDetermined
    var permissionAfterRequest: CameraPermission = .granted
    var captureResult: Result<Data, Error> = .success(Data([0x01]))
    var startError: Error?
    var toggleError: Error?
    private(set) var stopCount = 0
    private(set) var toggleCount = 0
    private(set) var isFlashOn = false
    private(set) var isUsingFrontCamera = false
    private(set) var displayZoomFactor: CGFloat = CameraZoom.standard
    private(set) var focusPoints: [CGPoint] = []

    /// Mirrors a typical iPhone: ultra-wide on the back, none on the front.
    var zoomOptions: [CGFloat] {
        isUsingFrontCamera ? [1, 2] : CameraZoom.presets
    }

    func toggleFlash() {
        isFlashOn.toggle()
    }

    func setDisplayZoom(_ factor: CGFloat) {
        displayZoomFactor = CameraZoom.clamp(factor, to: zoomOptions)
    }

    func focus(at point: CGPoint) {
        focusPoints.append(point)
    }

    var previewSession: AVCaptureSession? {
        nil
    }

    func requestPermission() async -> CameraPermission {
        permission = permissionAfterRequest
        return permission
    }

    func startSession() async throws {
        if let startError {
            throw startError
        }
    }

    func stopSession() {
        stopCount += 1
    }

    func toggleCamera() async throws {
        if let toggleError {
            throw toggleError
        }
        toggleCount += 1
        isUsingFrontCamera.toggle()
        displayZoomFactor = CameraZoom.standard
    }

    func capturePhoto() async throws -> Data {
        try captureResult.get()
    }
}
