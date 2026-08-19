import Foundation
import Observation

@MainActor
@Observable
public final class HistoryViewModel {
    public private(set) var completions: [CompletedChallenge] = []

    private let completedRepository: CompletedChallengeRepository
    private let photoRepository: PhotoRepository
    private let wardrobeRepository: WardrobeItemRepository
    private let thumbnails: GarmentThumbnailRepository
    private let previews: CompletionPreviewRepository
    private var renderedPreviews: [UUID: Data] = [:]

    public init(
        completedRepository: CompletedChallengeRepository,
        photoRepository: PhotoRepository,
        wardrobeRepository: WardrobeItemRepository,
        thumbnails: GarmentThumbnailRepository,
        previews: CompletionPreviewRepository
    ) {
        self.completedRepository = completedRepository
        self.photoRepository = photoRepository
        self.wardrobeRepository = wardrobeRepository
        self.thumbnails = thumbnails
        self.previews = previews
    }

    public func load() {
        completions = completedRepository.load().sorted { $0.completedAt > $1.completedAt }
        renderedPreviews = [:]
    }

    public func previewData(for completion: CompletedChallenge) -> Data? {
        if let file = completion.previewFile, let data = try? previews.data(forFile: file) {
            return data
        }
        return renderedPreviews[completion.id]
    }

    public func renderMissingPreview(for completion: CompletedChallenge) async {
        guard previewData(for: completion) == nil else { return }

        var originals: [String: Data] = [:]
        for id in Set(completion.document.photoIDs) {
            originals[id] = try? photoRepository.loadOriginal(id: id)
        }
        guard let data = try? await ExportService.render(
            originals: originals, document: completion.document
        ) else {
            return
        }
        renderedPreviews[completion.id] = data
    }

    public func garmentsWorn(in completion: CompletedChallenge) -> [(item: WardrobeItem, wearCount: Int)] {
        do {
            let items = try wardrobeRepository.items()
            var results: [(WardrobeItem, Int)] = []

            for item in items {
                let wears = try wardrobeRepository.wears(for: item.id)
                let wasWornInThisCompletion = wears.contains { $0.completionID == completion.id }
                if wasWornInThisCompletion {
                    results.append((item, wears.count))
                }
            }
            return results
        } catch {
            Log.report(error)
            return []
        }
    }

    public func thumbnailData(for item: WardrobeItem) -> Data? {
        try? thumbnails.data(forFile: item.cutoutFile)
    }
}
