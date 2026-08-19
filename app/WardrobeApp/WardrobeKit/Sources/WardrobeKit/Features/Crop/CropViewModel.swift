import CoreGraphics
import Foundation
import Observation

/// Loads the capture so it can be framed to 3:4 (PRD FR-083).
///
/// A view model of its own rather than more state on `CaptureFlowViewModel`,
/// for the same reason `EditorViewModel` is separate: crop is its own screen
/// with its own loading and its own failure, even though it is a stage of the
/// same flow.
@MainActor
@Observable
public final class CropViewModel {
    public private(set) var image: Loadable<CGImage> = .idle

    private let photoID: String
    private let photoRepository: PhotoRepository
    private(set) var loadTask: Task<Void, Never>?

    public init(photoID: String, photoRepository: PhotoRepository) {
        self.photoID = photoID
        self.photoRepository = photoRepository
    }

    /// 2048px is more than enough to frame by eye, and keeps the decode cheap.
    /// The export still crops the full-resolution original, so framing at this
    /// size costs no quality.
    /// `nonisolated`: an immutable number the detached decode reads, and the
    /// main actor has no claim on it.
    private nonisolated static let maxPreviewPixel: CGFloat = 2048

    public func load() {
        guard case .idle = image else { return }

        loadTask?.cancel()
        image = .loading

        loadTask = Task { [photoRepository, photoID] in
            do {
                // Decode stays off the main actor, as it does in the editor.
                let decoded = try await Task.detached(priority: .userInitiated) {
                    let data = try photoRepository.loadOriginal(id: photoID)
                    return ImageDecoding.downsampledImage(from: data, maxPixel: Self.maxPreviewPixel)
                }.value
                try Task.checkCancellation()
                // A photo that will not decode cannot be framed. FR-083 wants
                // that said plainly, with retake still on offer.
                image = decoded.map(Loadable.loaded) ?? .failed(.photoImportFailed)
            } catch is CancellationError {
                // Ignore cancellation.
            } catch {
                Log.report(error)
                image = .failed(AppError(wrapping: error))
            }
        }
    }
}
