@preconcurrency import AVFoundation
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

    func removeAll() {
        stored = []
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

    func update(_ item: WardrobeItem) throws {
        guard let index = storedItems.firstIndex(where: { $0.id == item.id }) else { return }
        storedItems[index] = item
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

// MARK: - Document fixtures and readers

extension EditorDocument {
    /// The same document with every photo layer pointed at `photoID`.
    func showingPhoto(_ photoID: String) -> EditorDocument {
        var copy = self
        copy.layers = layers.map { layer in
            guard case let .photo(content) = layer.content else { return layer }
            var updated = layer
            updated.content = .photo(PhotoContent(photoID: photoID, crop: content.crop))
            return updated
        }
        return copy
    }

    /// The bottom photo layer's crop — the single-photo shape most tests still
    /// speak in. Production says which layer it means (FR-093); a test with one
    /// photo has nothing to disambiguate.
    var firstPhotoCrop: CropSpec? {
        photoIDs.first
            .flatMap { photoLayerID(showing: $0) }
            .flatMap { crop(ofLayer: $0) }
    }

    /// The layer showing the first photo, for tests that need to name it.
    var firstPhotoLayerID: UUID? {
        photoIDs.first.flatMap { photoLayerID(showing: $0) }
    }

    /// Builds a document from the flat shape tests already read well in.
    /// Routed through the migration on purpose rather than reimplementing it —
    /// the migration has its own tests, so a break there fails loudly at the
    /// source instead of quietly here.
    static func fixture(
        photoID: String? = "photo-1",
        crop: CropSpec? = nil,
        texts: [TextItem] = [],
        stickers: [StickerItem] = [],
        background: CanvasBackground = .white
    ) -> EditorDocument {
        var document = EditorDocument(
            migrating: EditDraft(crop: crop, texts: texts, stickers: stickers),
            photoID: photoID
        )
        document.background = background
        return document
    }

    var textContents: [String] {
        layers.compactMap { layer in
            guard case let .text(text) = layer.content else { return nil }
            return text.content
        }
    }

    /// The flat projection, kept here because only tests still compare against
    /// the pre-canvas shape — production reads `EditorLayer.textDraft`.
    var textItems: [TextItem] {
        layers.compactMap { layer in
            guard case let .text(text) = layer.content else { return nil }
            return TextItem(
                id: layer.id,
                content: text.content,
                position: layer.transform.position,
                scale: layer.transform.scale,
                rotationDegrees: layer.transform.rotationDegrees,
                colorName: text.colorName,
                hasBackground: text.backgroundStyle == .solid,
                fontName: text.fontName,
                alignmentName: text.alignmentName
            )
        }
    }

    var stickerItems: [StickerItem] {
        layers.compactMap { layer -> StickerItem? in
            guard case let .sticker(sticker) = layer.content,
                  case let .emoji(glyph)? = sticker.art.design
            else {
                return nil
            }
            return StickerItem(
                id: layer.id,
                emoji: glyph,
                position: layer.transform.position,
                scale: layer.transform.scale,
                rotationDegrees: layer.transform.rotationDegrees
            )
        }
    }

    var stickerEmojis: [String] {
        stickerItems.map(\.emoji)
    }

    var stickerArts: [StickerArt] {
        layers.compactMap { layer in
            guard case let .sticker(sticker) = layer.content else { return nil }
            return sticker.art
        }
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
}
