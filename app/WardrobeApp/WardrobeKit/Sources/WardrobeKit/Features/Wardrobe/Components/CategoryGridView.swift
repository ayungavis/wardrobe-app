import DesignSystem
import SwiftUI

struct CategoryGridView: View {
    let category: GarmentCategory
    let items: [WardrobeItem]
    let thumbnailData: (WardrobeItem) -> Data?
    let wearCount: (WardrobeItem) -> Int
    let namespace: Namespace.ID
    let onClose: () -> Void
    let onSelect: (WardrobeItem) -> Void
    @Binding var sortOrder: WardrobeView.SortOrder
    
    private let columns = [
        GridItem(.flexible(), spacing: Spacing.md),
        GridItem(.flexible(), spacing: Spacing.md),
    ]
    
    private var sortedItems: [WardrobeItem] {
        switch sortOrder {
        case .mostUsed: items.sorted { wearCount($0) > wearCount($1) }
        case .leastUsed: items.sorted { wearCount($0) < wearCount($1) }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onClose) {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "chevron.left")
                        Text(category.title, bundle: .module)
                            
                    }
                    .foregroundStyle(AppColor.textPrimary)
                    .font(AppFont.roundedTitle)
                    .fontWeight(.semibold)
                }
                Spacer()
                Menu {
                    Picker("", selection: $sortOrder) {
                        ForEach(WardrobeView.SortOrder.allCases, id: \.self) { order in
                            Text(order.title, bundle: .module).tag(order)
                        }
                    }
                } label: {
                    Label {
                        Text("wardrobe.filter", bundle: .module) } icon: {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                        }
                        .font(AppFont.roundedTitle2)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColor.textPrimary)
                        .padding(.vertical, Spacing.sm)
                        .padding(.horizontal, Spacing.md)
                        .background(Capsule()
                                    
                            .fill(.clear)
                            .glassEffect(.clear)
                        )
                }
            }
            .padding(Spacing.lg)
            
            ScrollView {
                LazyVGrid(columns: columns, spacing: Spacing.md) {
                    ForEach(sortedItems) { item in
                        Button {
                            onSelect(item)
                        } label: {
                            WardrobeItemCellView(item: item, data: thumbnailData(item), wearCount: wearCount(item))
                                .matchedGeometryEffect(id: item.id, in: namespace)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(Spacing.lg)
            }
        }
    }
}
