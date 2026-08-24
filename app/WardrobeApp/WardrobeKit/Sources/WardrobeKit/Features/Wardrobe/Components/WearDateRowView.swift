import DesignSystem
import SwiftUI

struct WearDateRowView: View {
    let wornAt: Date?
    let onPick: (Date) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            DatePicker(
                selection: Binding(get: { wornAt ?? .now }, set: onPick),
                displayedComponents: .date
            ) {
                Text("wardrobe.review.wearDate", bundle: .module)
                    .font(AppFont.body)
                    .foregroundStyle(AppColor.textPrimary)
            }

            if wornAt == nil {
                Text("wardrobe.review.wearDate.missing", bundle: .module)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.warning)
            }
        }
        .accessibilityIdentifier("wardrobe.review.wearDate")
    }
}
