import DesignSystem
import SwiftUI

struct WearTimelineView: View {
    let wears: [WearRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            ForEach(wears) { wear in
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 6))
                        .foregroundStyle(AppColor.accent)
                    Text(wear.wornAt, format: .dateTime.day().month(.wide).year())
                        .font(AppFont.body)
                        .foregroundStyle(AppColor.textPrimary)
                    Spacer()
                    if wear.completionID == nil {
                        Text("wardrobe.detail.wear.imported", bundle: .module)
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }
            }
        }
    }
}
