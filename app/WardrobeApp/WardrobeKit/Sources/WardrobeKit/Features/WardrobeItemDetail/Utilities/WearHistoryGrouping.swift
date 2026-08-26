import Foundation

enum WearHistoryGrouping {
    static func groups(for wears: [WearRecord]) -> [WearHistoryGroup] {
        let calendar = Calendar.current
        let now = Date()

        let buckets = Dictionary(grouping: wears) { wear in
            calendar.dateInterval(of: .weekOfYear, for: wear.wornAt)?.start ?? wear.wornAt
        }

        let currentWeekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start

        return buckets
            .sorted { $0.key > $1.key }
            .map { weekStart, wearsInWeek in
                let sorted = wearsInWeek.sorted { $0.wornAt > $1.wornAt }
                let isCurrentWeek = weekStart == currentWeekStart

                let title = isCurrentWeek
                    ? String(localized: "wardrobe.detail.wearHistory.thisWeek", bundle: .module)
                    : weekRangeTitle(weekStart: weekStart, calendar: calendar)

                let entries = sorted.map { wear in
                    WearHistoryEntry(
                        label: isCurrentWeek
                            ? wear.wornAt.formatted(.dateTime.weekday(.wide))
                            : wear.wornAt.formatted(.dateTime.day().month(.abbreviated).year(.twoDigits))
                    )
                }

                return WearHistoryGroup(title: title, entries: entries)
            }
    }

    private static func weekRangeTitle(weekStart: Date, calendar: Calendar) -> String {
        guard let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) else {
            return weekStart.formatted(.dateTime.day().month(.abbreviated))
        }
        let start = weekStart.formatted(.dateTime.day().month(.abbreviated))
        let end = weekEnd.formatted(.dateTime.day().month(.abbreviated))
        return String(
            localized: "wardrobe.detail.wearHistory.weekRange \(start) \(end)",
            bundle: .module
        )
    }
}
