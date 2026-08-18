import CoreGraphics
import Foundation
@testable import WardrobeKit

/// Shared by the editor suites, split by subject because one struct outgrew
/// SwiftLint's body limit — the editor has a lot of subjects.
final class SpyLibrarySaver: PhotoLibrarySaveService, @unchecked Sendable {
    var saveError: Error?
    private(set) var savedData: [Data] = []

    func save(_ data: Data) async throws {
        if let saveError {
            throw saveError
        }
        savedData.append(data)
    }
}

@MainActor
func makeEditorSUT(
    activeRepository: InMemoryActiveChallengeRepository = InMemoryActiveChallengeRepository(),
    photoRepository: SpyPhotoRepository = SpyPhotoRepository(),
    librarySaver: SpyLibrarySaver = SpyLibrarySaver(),
    document: EditorDocument? = nil
) throws -> EditorViewModel {
    let photoID = try photoRepository.saveOriginal(SampleCameraService.makeSampleJPEG(width: 100, height: 200))
    var challenge = ActiveChallenge(card: ChallengeCard(prompt: "x"), acceptedAt: .distantPast)
    challenge.photoID = photoID
    challenge.document = document ?? EditorDocument(photoID: photoID)
    activeRepository.stored = challenge
    return EditorViewModel(
        challenge: challenge,
        activeRepository: activeRepository,
        photoRepository: photoRepository,
        librarySaver: librarySaver
    )
}
