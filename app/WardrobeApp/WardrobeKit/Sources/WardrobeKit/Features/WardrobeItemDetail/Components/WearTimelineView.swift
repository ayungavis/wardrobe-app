import DesignSystem
import SwiftUI

/// Every occasion this garment was worn, newest first.
///
/// The list is the point: a count alone says how much, while the dates say
/// when — which is what tells someone whether a garment is in rotation or was
/// worn once in March.
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
                        // Imported outside the daily loop, which is worth saying:
                        // it explains a wear with no challenge behind it.
                        Text("wardrobe.detail.wear.imported", bundle: .module)
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }
            }
        }
    }
}
