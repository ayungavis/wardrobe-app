import DesignSystem
import SwiftUI

struct GarmentDiscardHeaderView: View {
    let titleKey: LocalizedStringKey
    let messageKey: LocalizedStringKey

    var body: some View {
        VStack(spacing: Spacing.sm) {
            Text(titleKey, bundle: .module)
                .font(AppFont.title.weight(.bold))
                .foregroundStyle(AppColor.textPrimary)
            Text(messageKey, bundle: .module)
                .font(AppFont.body)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}
