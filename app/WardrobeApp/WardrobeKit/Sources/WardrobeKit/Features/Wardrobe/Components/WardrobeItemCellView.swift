import DesignSystem
import SwiftUI

struct WardrobeItemCellView: View {
    let item: ClothingItem

    private static let thumbnailHeight: CGFloat = 150

    var body: some View {
        VStack(spacing: Spacing.xs) {
            // ponytail: reads the file on each body pass; fine for a few dozen
            // items, revisit when the wardrobe grows past a screenful.
            if let data = try? Data(contentsOf: URL(filePath: item.thumbnailPath)) {
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
