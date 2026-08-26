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
