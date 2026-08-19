import DesignSystem
import SwiftUI

struct WardrobeSearchResultsView: View {
    let items: [WardrobeItem]
    let thumbnailData: (WardrobeItem) -> Data?
    let wearCount: (WardrobeItem) -> Int
    let onSelect: (WardrobeItem) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: Spacing.md),
        GridItem(.flexible(), spacing: Spacing.md),
    ]

    var body: some View {
        if items.isEmpty {
            ContentUnavailableView {
                Label {
                    Text("wardrobe.search.empty.title", bundle: .module)
                } icon: {
                    Image(systemName: "magnifyingglass")
                }
            } description: {
                Text("wardrobe.search.empty.message", bundle: .module)
            }
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: Spacing.md) {
                    ForEach(items) { item in
                        Button {
                            onSelect(item)
                        } label: {
                            WardrobeItemCellView(
                                item: item, data: thumbnailData(item), wearCount: wearCount(item)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(Spacing.lg)
            }
        }
    }
}
