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

final class FakeLibraryPreview: PhotoLibraryPreviewing, @unchecked Sendable {
    var thumbnail: CGImage?

    func latestPhotoThumbnail(maxPixel _: CGFloat) async -> CGImage? {
        thumbnail
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
