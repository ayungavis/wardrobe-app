@preconcurrency import AVFoundation
import Foundation
@testable import WardrobeKit

final class InMemoryActiveChallengeStore: ActiveChallengeStore, @unchecked Sendable {
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

final class SpyPhotoStore: PhotoStore, @unchecked Sendable {
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
    }

    func capturePhoto() async throws -> Data {
        try captureResult.get()
    }
}
