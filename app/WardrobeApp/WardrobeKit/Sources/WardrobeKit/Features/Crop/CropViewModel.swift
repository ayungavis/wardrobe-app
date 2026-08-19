import CoreGraphics
import Foundation
import Observation

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

    private nonisolated static let maxPreviewPixel: CGFloat = 2048

    public func load() {
        guard case .idle = image else { return }

        loadTask?.cancel()
        image = .loading

        loadTask = Task { [photoRepository, photoID] in
            do {
                let decoded = try await Task.detached(priority: .userInitiated) {
                    let data = try photoRepository.loadOriginal(id: photoID)
                    return ImageDecoding.downsampledImage(from: data, maxPixel: Self.maxPreviewPixel)
                }.value
                try Task.checkCancellation()
                // A photo that will not decode cannot be framed. FR-083 wants
                // that said plainly, with retake still on offer.
                image = decoded.map(Loadable.loaded) ?? .failed(.photoImportFailed)
            } catch is CancellationError {
            } catch {
                Log.report(error)
                image = .failed(AppError(wrapping: error))
            }
        }
    }
}
