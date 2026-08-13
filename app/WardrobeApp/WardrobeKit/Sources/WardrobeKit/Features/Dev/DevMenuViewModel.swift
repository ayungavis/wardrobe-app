import Foundation
import Observation

/// What the dev menu shows about the current persisted state. Rebuilding it is
/// cheap (two UserDefaults reads), so it is recomputed after every action.
public struct DevStateSummary: Equatable, Sendable {
    public var completionCount = 0
    public var hasCompletedToday = false
    public var hasActiveChallenge = false
    public var activeHasPhoto = false
}

@MainActor
@Observable
public final class DevMenuViewModel {
    public private(set) var summary = DevStateSummary()
    /// Last action's result, shown inline so a tap has visible feedback.
    public private(set) var lastAction: String?

    private let store: ActiveChallengeStore
    private let completedStore: CompletedChallengeStore
    private let photoStore: PhotoStore
    private let calendar: Calendar

    public init(
        store: ActiveChallengeStore,
        completedStore: CompletedChallengeStore,
        photoStore: PhotoStore,
        calendar: Calendar = .current
    ) {
        self.store = store
        self.completedStore = completedStore
        self.photoStore = photoStore
        self.calendar = calendar
    }

    public func refresh() {
        let active = store.load()
        summary = DevStateSummary(
            completionCount: completedStore.load().count,
            hasCompletedToday: completedStore.hasCompletion(on: Date(), calendar: calendar),
            hasActiveChallenge: active != nil,
            activeHasPhoto: active?.photoID != nil
        )
    }

    /// Puts today back to a clean slate: today's completion, the active
    /// challenge, and both of their photos are gone, so the deck reopens.
    public func resetToday() {
        let today = Date()

        let todaysCompletions = completedStore.load()
            .filter { calendar.isDate($0.completedAt, inSameDayAs: today) }
        for completion in todaysCompletions {
            deletePhoto(completion.photoID)
        }
        completedStore.removeCompletions(on: today)

        if let photoID = store.load()?.photoID {
            deletePhoto(photoID)
        }
        store.clear()

        refresh()
        lastAction = "Today's challenge reset"
        Log.ui.info("Dev: today's challenge reset")
    }

    private func deletePhoto(_ id: String) {
        do {
            try photoStore.deleteOriginal(id: id)
        } catch {
            Log.report(error) // an orphaned file must not block the reset
        }
    }
}
