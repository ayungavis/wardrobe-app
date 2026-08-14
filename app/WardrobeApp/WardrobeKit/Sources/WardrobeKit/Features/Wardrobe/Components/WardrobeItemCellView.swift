import DesignSystem
import SwiftUI

struct WardrobeItemCellView: View {
    let item: WardrobeItem
    let data: Data?

    private static let thumbnailHeight: CGFloat = 150

    var body: some View {
        VStack(spacing: Spacing.xs) {
            if let data {
                DownsampledPhotoView(data: data)
                    .frame(height: Self.thumbnailHeight)
                    .frame(maxWidth: .infinity)
                    .background(AppColor.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(AppColor.surface)
                    .frame(height: Self.thumbnailHeight)
            }

            Text(item.category.title, bundle: .module)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
        }
    }
}

extension GarmentCategory {
    var title: LocalizedStringKey {
        switch self {
        case .top: "wardrobe.filter.top"
        case .bottom: "wardrobe.filter.bottom"
        }
    }
}
