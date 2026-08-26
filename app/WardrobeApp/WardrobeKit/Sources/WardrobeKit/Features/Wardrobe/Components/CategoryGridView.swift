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
    @Binding var sortOrder: WardrobeViewModel.SortOrder

    private let columns = [
        GridItem(.flexible(), spacing: Spacing.md),
        GridItem(.flexible(), spacing: Spacing.md),
    ]

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
                    Picker(String(), selection: $sortOrder) {
                        ForEach(WardrobeViewModel.SortOrder.allCases, id: \.self) { order in
                            Text(order.title, bundle: .module).tag(order)
                        }
                    }
                } label: {
                    Label {
                        Text("wardrobe.filter", bundle: .module)
                    } icon: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                    .font(AppFont.roundedTitle2)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColor.textPrimary)
                    .padding(.vertical, Spacing.sm)
                    .padding(.horizontal, Spacing.md)
                    .glassEffect(.regular, in: .capsule)
                }
            }
            .padding(Spacing.lg)

            ScrollView {
                LazyVGrid(columns: columns, spacing: Spacing.md) {
                    ForEach(items) { item in
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
