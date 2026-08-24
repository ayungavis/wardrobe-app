//
//  WearHistoryPopoverView.swift
//  WardrobeKit
//
//  Created by Luisa Haning Tyas on 22/08/26.
//

import DesignSystem
import SwiftUI

struct WearHistoryPopoverView: View {
    let wears: [WearRecord]

    private var groups: [WearHistoryGroup] {
        WearHistoryGrouping.groups(for: wears)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                Text("wardrobe.detail.wearHistory.title", bundle: .module)
                    .font(AppFont.title)
                    .foregroundStyle(AppColor.textPrimary)

                if groups.isEmpty {
                    Text("history.detail.garments.empty", bundle: .module)
                        .font(AppFont.body)
                        .foregroundStyle(AppColor.textSecondary)
                } else {
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text(group.title)
                                .font(AppFont.body.weight(.semibold))
                                .foregroundStyle(AppColor.textPrimary)

                            ForEach(group.entries) { entry in
                                HStack(spacing: Spacing.sm) {
                                    Image(systemName: "circle.fill")
                                        .font(.system(size: 4))
                                        .foregroundStyle(AppColor.accent)
                                    Text(entry.label)
                                        .font(AppFont.caption)
                                        .foregroundStyle(AppColor.textSecondary)
                                }
                            }
                        }
                    }
                }
            }
            .padding(Spacing.sm)
        }
        .frame(width: 260, height: 320)
    }
}

// MARK: - Grouping

private struct WearHistoryGroup: Identifiable {
    let id = UUID()
    let title: String
    let entries: [WearHistoryEntry]
}

private struct WearHistoryEntry: Identifiable {
    let id = UUID()
    let label: String
}

private enum WearHistoryGrouping {
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
        return "\(start) – \(end)"
    }
}
