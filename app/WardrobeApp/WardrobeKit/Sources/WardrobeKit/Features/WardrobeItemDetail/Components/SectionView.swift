import DesignSystem
import SwiftUI

struct SectionView<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(title, bundle: .module)
                .font(AppFont.title)
                .foregroundStyle(AppColor.textPrimary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
