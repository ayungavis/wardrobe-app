import Foundation

enum ConflictCounting {
    @MainActor
    static func openCount(
        wardrobe: WardrobeItemRepository,
        completions: CompletedChallengeRepository?,
        calendar: Calendar = .current
    ) -> Int {
        let items = ((try? wardrobe.openConflicts()) ?? []).count
        let days = completions.map { repository in
            Set(
                repository.load()
                    .filter { $0.status == .conflicting && !$0.isDeliberateExtra }
                    .map { calendar.startOfDay(for: $0.completedAt) }
            ).count
        } ?? 0
        return items + days
    }
}
