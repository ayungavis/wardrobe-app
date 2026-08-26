import DesignSystem
import SwiftUI

struct SimilarItemCellView: View {
    let entry: SimilarItem
    let data: Data?
    var onMerge: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Group {
                if let data {
                    DownsampledPhotoView(data: data)
                } else {
                    RoundedRectangle(cornerRadius: 12).fill(AppColor.surface)
                }
            }
            .frame(width: 110, height: 110)
            .background(AppColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Text(entry.match.confidence.title, bundle: .module)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)

            if let onMerge {
                Button(action: onMerge) {
                    Text("wardrobe.detail.merge.button", bundle: .module)
                        .font(AppFont.caption.bold())
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(Text("wardrobe.detail.merge.hint", bundle: .module))
            }
        }
        .frame(width: 110)
    }
}
