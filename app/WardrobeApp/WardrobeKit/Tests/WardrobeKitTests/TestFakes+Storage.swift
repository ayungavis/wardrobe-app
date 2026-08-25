import CoreGraphics
import Foundation
@testable import WardrobeKit

// The two file-backed repositories, faked in memory. Split out of
// `TestFakes.swift` only because that file reached the length limit.

final class InMemoryCompletionPreviewRepository: CompletionPreviewRepository, @unchecked Sendable {
    var files: [String: Data] = [:]
    private(set) var deleteAllCount = 0
    /// Set to make saving fail, which is how the "✓ still completes when the
    /// render cannot be stored" case is written.
    var saveError: Error?

    func save(_ data: Data, id: UUID) throws -> String {
        if let saveError {
            throw saveError
        }
        let file = "\(id.uuidString).jpg"
        files[file] = data
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

final class InMemoryGarmentThumbnailRepository: GarmentThumbnailRepository, @unchecked Sendable {
    var files: [String: Data] = [:]
    private(set) var deleteAllCount = 0

    func save(_: CGImage, id: UUID) throws -> String {
        let file = "\(id.uuidString).png"
        files[file] = Data([0x01])
        return file
    }

    func save(_ data: Data, id: UUID) throws -> String {
        let file = "\(id.uuidString).png"
        files[file] = data
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

@MainActor
final class InMemoryOutboxStore: OutboxStore {
    private var staged: [OutboxEnvelope] = []
    private var saved: [OutboxEnvelope] = []

    func stage(_ envelope: OutboxEnvelope) {
        staged.append(envelope)
    }

    func append(_ envelope: OutboxEnvelope) throws {
        stage(envelope)
        saved = ordered(staged)
    }

    func all() throws -> [OutboxEnvelope] {
        saved
    }

    func due(at date: Date, limit: Int) throws -> [OutboxEnvelope] {
        saved.filter { $0.state == .pending && $0.nextAttemptAt <= date }.prefix(limit).map(\.self)
    }

    func update(_ envelope: OutboxEnvelope) throws {
        guard let index = saved.firstIndex(where: { $0.id == envelope.id }) else {
            throw AppError.unexpected
        }
        saved[index] = envelope
        staged = saved
    }

    func remove(id: UUID) throws {
        saved.removeAll { $0.id == id }
        staged = saved
    }

    func removeAll() throws {
        saved = []
        staged = []
    }

    private func ordered(_ envelopes: [OutboxEnvelope]) -> [OutboxEnvelope] {
        envelopes.sorted { $0.createdAt < $1.createdAt }
    }
}

@MainActor
final class InMemoryCursorStore: CursorStore {
    private var committed: Int64 = 0
    private var staged: Int64?

    func position() throws -> Int64 {
        committed
    }

    func stage(position: Int64) throws {
        staged = position
    }

    func commit() throws {
        if let staged {
            committed = staged
        }
        staged = nil
    }

    func discard() {
        staged = nil
    }

    func reset() throws {
        committed = 0
        staged = nil
    }
}

@MainActor
final class InMemoryDiagnosticsStore: DiagnosticsStore {
    private var stored: [DiagnosticEntry] = []

    func record(_ error: Error, context: Log.Context, at date: Date) throws {
        stored.insert(DiagnosticEntry(
            id: UUID(), at: date, message: String(describing: error),
            operation: context.operation, endpoint: context.endpoint,
            requestID: context.requestID, status: context.status
        ), at: 0)
    }

    func entries() throws -> [DiagnosticEntry] {
        stored
    }

    func removeAll() throws {
        stored = []
    }
}

final class InMemoryMediaCacheStore: MediaCacheStore, @unchecked Sendable {
    // @unchecked: tests drive it from one actor at a time.
    private var stored: [UUID: Data] = [:]

    func data(for id: UUID) -> Data? {
        stored[id]
    }

    func store(_ data: Data, for id: UUID) throws {
        stored[id] = data
    }

    func removeAll() throws {
        stored = [:]
    }
}

@MainActor
final class InMemoryMediaUploadStore: MediaUploadStore {
    private var rows: [MediaUpload] = []

    func stage(_ upload: MediaUpload) {
        rows.append(upload)
    }

    func all() throws -> [MediaUpload] {
        rows.sorted { $0.createdAt < $1.createdAt }
    }

    func due(at date: Date, limit: Int) throws -> [MediaUpload] {
        rows.filter { $0.state == .pending && $0.nextAttemptAt <= date }.prefix(limit).map(\.self)
    }

    func hasRows(owner: UUID) throws -> Bool {
        rows.contains { $0.ownerID == owner }
    }

    func update(_ upload: MediaUpload) throws {
        guard let index = rows.firstIndex(where: { $0.id == upload.id }) else {
            throw AppError.unexpected
        }
        rows[index] = upload
    }

    func remove(id: UUID) throws {
        rows.removeAll { $0.id == id }
    }

    func removeAll() throws {
        rows = []
    }
}

@MainActor
final class StubMediaRepository: MediaRepository {
    var error: AppError?
    private(set) var uploadedIDs: [UUID] = []

    func upload(_: Data, id: UUID, kind _: MediaKind, contentType _: String) async throws {
        if let error {
            throw error
        }
        uploadedIDs.append(id)
    }

    var downloads: [UUID: Data] = [:]
    var failingIDs: Set<UUID> = []

    func data(for id: UUID) async throws -> Data {
        if failingIDs.contains(id) {
            throw AppError.unavailable
        }
        if let data = downloads[id] {
            return data
        }
        throw AppError.unexpected
    }

    func clearCache() throws {}
}

@MainActor
func makeInMemoryUploads() -> StoredMediaUploadRepository {
    StoredMediaUploadRepository(
        store: InMemoryMediaUploadStore(),
        photos: SpyPhotoRepository(),
        previews: InMemoryCompletionPreviewRepository(),
        thumbnails: InMemoryGarmentThumbnailRepository()
    )
}

@MainActor
func makeGrantedPreferences() -> InMemoryAccountPreferencesRepository {
    let preferences = InMemoryAccountPreferencesRepository()
    preferences.stored = AccountPreferences(uploadConsentAt: Date())
    return preferences
}
