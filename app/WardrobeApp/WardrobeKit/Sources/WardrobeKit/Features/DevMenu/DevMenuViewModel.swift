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
    private let calendar: Calendar

    public init(
        activeRepository: ActiveChallengeRepository,
        completedRepository: CompletedChallengeRepository,
        photoRepository: PhotoRepository,
        calendar: Calendar = .current
    ) {
        self.activeRepository = activeRepository
        self.completedRepository = completedRepository
        self.photoRepository = photoRepository
        self.calendar = calendar
    }

    public func refresh() {
        let active = activeRepository.load()
        summary = DevStateSummary(
            completionCount: completedRepository.load().count,
            hasCompletedToday: completedRepository.hasCompletion(on: Date(), calendar: calendar),
            hasActiveChallenge: active != nil,
            activeHasPhoto: active?.photoID != nil
        )
    }

    /// Puts today back to a clean slate: today's completion, the active
    /// challenge, and both of their photos are gone, so the deck reopens.
    public func resetToday() {
        let today = Date()

        let todaysCompletions = completedRepository.load()
            .filter { calendar.isDate($0.completedAt, inSameDayAs: today) }
        for completion in todaysCompletions {
            deletePhoto(completion.photoID)
        }
        completedRepository.removeCompletions(on: today)

        if let photoID = activeRepository.load()?.photoID {
            deletePhoto(photoID)
        }
        activeRepository.clear()

        refresh()
        lastAction = "Today's challenge reset"
        Log.ui.info("Dev: today's challenge reset")
    }

    private func deletePhoto(_ id: String) {
        do {
            try photoRepository.deleteOriginal(id: id)
        } catch {
            Log.report(error) // an orphaned file must not block the reset
        }
    }
}
