import Foundation
import Observation

@MainActor
@Observable
public final class DevMenuViewModel {
    public private(set) var summary = DevStateSummary()
    public private(set) var lastAction: String?

    private let activeRepository: ActiveChallengeRepository
    private let completedRepository: CompletedChallengeRepository
    private let photoRepository: PhotoRepository
    private let wardrobeRepository: WardrobeItemRepository
    private let thumbnails: GarmentThumbnailRepository
    private let previews: CompletionPreviewRepository
    private let calendar: Calendar

    public init(
        activeRepository: ActiveChallengeRepository,
        completedRepository: CompletedChallengeRepository,
        photoRepository: PhotoRepository,
        wardrobeRepository: WardrobeItemRepository,
        thumbnails: GarmentThumbnailRepository,
        previews: CompletionPreviewRepository,
        calendar: Calendar = .current
    ) {
        self.activeRepository = activeRepository
        self.completedRepository = completedRepository
        self.photoRepository = photoRepository
        self.wardrobeRepository = wardrobeRepository
        self.thumbnails = thumbnails
        self.previews = previews
        self.calendar = calendar
    }

    public func refresh() {
        let active = activeRepository.load()
        summary = DevStateSummary(
            completionCount: completedRepository.load().count,
            hasCompletedToday: completedRepository.hasCompletion(on: Date(), calendar: calendar),
            hasActiveChallenge: active != nil,
            activeHasPhoto: active?.photoID != nil,
            wardrobeItemCount: (try? wardrobeRepository.items().count) ?? 0,
            fingerprintCount: (try? wardrobeRepository.fingerprints().count) ?? 0
        )
    }

    public func resetWardrobe() {
        do {
            try wardrobeRepository.deleteAll()
            try thumbnails.deleteAll()
            Log.ui.info("Dev: wardrobe reset")
        } catch {
            Log.report(error)
        }
        refresh()
        lastAction = "Wardrobe cleared"
    }

    public func resetToday() {
        let today = Date()

        let todaysCompletions = completedRepository.load()
            .filter { calendar.isDate($0.completedAt, inSameDayAs: today) }
        for completion in todaysCompletions {
            photoRepository.deleteOriginals(of: completion.document, and: completion.photoID)
            deletePreview(of: completion)
        }
        completedRepository.removeCompletions(on: today)

        if let active = activeRepository.load() {
            photoRepository.deleteOriginals(of: active.document, and: active.photoID)
            photoRepository.deleteUnusedOriginals(
                of: active.document, imported: active.importedPhotoIDs
            )
        }
        activeRepository.clear()

        refresh()
        lastAction = "Today's challenge reset"
        Log.ui.info("Dev: today's challenge reset")
    }

    public func resetHistory() {
        for completion in completedRepository.load() {
            photoRepository.deleteOriginals(of: completion.document, and: completion.photoID)
        }
        do {
            try previews.deleteAll()
        } catch {
            Log.report(error)
        }
        completedRepository.removeAll()

        refresh()
        lastAction = "History cleared"
        Log.ui.info("Dev: history cleared")
    }

    private func deletePreview(of completion: CompletedChallenge) {
        guard let file = completion.previewFile else { return }
        do {
            try previews.delete(file: file)
        } catch {
            Log.report(error)
        }
    }
}
