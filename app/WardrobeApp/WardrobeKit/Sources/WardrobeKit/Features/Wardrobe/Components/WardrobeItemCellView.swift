import DesignSystem
import SwiftUI

struct WardrobeItemCellView: View {
    let item: WardrobeItem
    let data: Data?
    let wearCount: Int
    
    private static let thumbnailHeight: CGFloat = 150
    
    var body: some View {
        VStack(spacing: Spacing.xs) {
            ZStack(alignment: .bottomTrailing) {
                if let data {
                    DownsampledPhotoView(data: data)
                        .frame(height: Self.thumbnailHeight)
                        .frame(maxWidth: .infinity)
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(AppColor.surface)
                        .frame(height: Self.thumbnailHeight)
                }
                
                Text("\(wearCount)x")
                    .font(AppFont.title.bold())
                    .stroke(color: .white, width: 3)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, 4)
                    //.background(Capsule().fill(.white))
                    .padding(Spacing.sm)
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
