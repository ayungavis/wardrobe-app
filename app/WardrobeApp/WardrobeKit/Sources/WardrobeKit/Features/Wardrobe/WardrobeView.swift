import DesignSystem
import SwiftUI

/// PRD §17: the wardrobe grows from completed challenges, so this screen only
/// shows what is already there.
public struct WardrobeView: View {
    @State private var viewModel: WardrobeViewModel
    @State private var filter: CategoryFilter = .all

    public init(viewModel: WardrobeViewModel) {
        _viewModel = State(wrappedValue: viewModel)
    }

    enum CategoryFilter: CaseIterable {
        case all, top, bottom

        var category: GarmentCategory? {
            switch self {
            case .all: nil
            case .top: .top
            case .bottom: .bottom
            }
        }
    }

    private var filteredItems: [WardrobeItem] {
        guard let category = filter.category else { return viewModel.items }
        return viewModel.items.filter { $0.category == category }
    }

    private let columns = [
        GridItem(.flexible(), spacing: Spacing.md),
        GridItem(.flexible(), spacing: Spacing.md),
    ]

    public var body: some View {
        NavigationStack {
            Group {
                if viewModel.items.isEmpty {
                    emptyState
                } else {
                    content
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppColor.background)
            .navigationTitle(Text("tab.wardrobe", bundle: .module))
        }
        .task { viewModel.load() }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label {
                Text("wardrobe.empty.title", bundle: .module)
            } icon: {
                Image(systemName: "tshirt")
            }
        } description: {
            Text("wardrobe.empty.message", bundle: .module)
        }
    }

    private var content: some View {
        VStack(spacing: Spacing.md) {
            Picker(String(localized: "wardrobe.filter", bundle: .module), selection: $filter) {
                ForEach(CategoryFilter.allCases, id: \.self) { option in
                    Text(option.title, bundle: .module).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Spacing.lg)

            ScrollView {
                LazyVGrid(columns: columns, spacing: Spacing.md) {
                    ForEach(filteredItems) { item in
                        // ponytail: reads the file on each body pass; fine for a
                        // few dozen items, revisit when the wardrobe outgrows a
                        // screenful.
                        WardrobeItemCellView(item: item, data: viewModel.thumbnailData(for: item))
                    }
                }
                .padding(Spacing.lg)
            }
        }
    }
}

private extension WardrobeView.CategoryFilter {
    var title: LocalizedStringKey {
        switch self {
        case .all: "wardrobe.filter.all"
        case .top: "wardrobe.filter.top"
        case .bottom: "wardrobe.filter.bottom"
        }
    }
}

#Preview {
    WardrobeView(viewModel: AppContainer().makeWardrobeViewModel())
}
