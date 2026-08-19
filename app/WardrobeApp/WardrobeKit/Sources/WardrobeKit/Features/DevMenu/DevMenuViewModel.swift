import Foundation
import Observation

// What the dev menu shows about the current persisted state. Rebuilding it is
// cheap (two UserDefaults reads), so it is recomputed after every action.

@MainActor
@Observable
public final class DevMenuViewModel {
    public private(set) var summary = DevStateSummary()
    /// Last action's result, shown inline so a tap has visible feedback.
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

    /// Empties the wardrobe: rows first, then the cut-out files, so a failure
    /// halfway cannot leave rows pointing at images that are already gone.
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

    /// Puts today back to a clean slate: today's completion, the active
    /// challenge, and every photo either of them holds are gone, so the deck
    /// reopens.
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
            // Photos added and then deleted have nothing left in the document
            // to name them, so this is the last chance to clean them up.
            photoRepository.deleteUnusedOriginals(
                of: active.document, imported: active.importedPhotoIDs
            )
        }
        activeRepository.clear()

        refresh()
        lastAction = "Today's challenge reset"
        Log.ui.info("Dev: today's challenge reset")
    }

    /// Empties the whole history, photos included. The wardrobe is deliberately
    /// untouched: the wear records those completions created stay, and "Reset
    /// wardrobe" is the button that clears them.
    public func resetHistory() {
        for completion in completedRepository.load() {
            photoRepository.deleteOriginals(of: completion.document, and: completion.photoID)
        }
        // Everything goes, so the directory goes — no per-file walk needed, and
        // it collects any preview whose completion was already lost.
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

    /// Reported rather than thrown, like the photos above: an orphaned file is
    /// not worth blocking a reset over.
    private func deletePreview(of completion: CompletedChallenge) {
        guard let file = completion.previewFile else { return }
        do {
            try previews.delete(file: file)
        } catch {
            Log.report(error)
        }
    }
}
