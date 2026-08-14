import DesignSystem
import PhotosUI
import SwiftUI

// ponytail: temporary bulk-scan UI for exercising the detector. The real
// wardrobe fills from completed challenges (see docs/wardrobe-generation.md).
public struct WardrobeView: View {
    @State private var viewModel: WardrobeViewModel
    @State private var selectedPhotos: [PhotosPickerItem] = []
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

    private var filteredItems: [ClothingItem] {
        guard let category = filter.category else { return viewModel.items }
        return viewModel.items.filter { $0.category == category }
    }

    private let columns = [
        GridItem(.flexible(), spacing: Spacing.md),
        GridItem(.flexible(), spacing: Spacing.md),
    ]

    public var body: some View {
        VStack(spacing: Spacing.md) {
            scanButton
            filterPicker
            grid
        }
        .background(AppColor.background)
    }

    private var scanButton: some View {
        PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 20, matching: .images) {
            if viewModel.isScanning {
                HStack(spacing: Spacing.xs) {
                    Text("wardrobe.scan.processing", bundle: .module)
                    Text(verbatim: "\(Int(viewModel.scanProgress * 100))%")
                }
            } else {
                Text("wardrobe.scan.add", bundle: .module)
            }
        }
        .disabled(viewModel.isScanning)
        .buttonStyle(.borderedProminent)
        .tint(AppColor.accent)
        .padding(Spacing.lg)
        .onChange(of: selectedPhotos) { _, newItems in
            Task { await scan(newItems) }
        }
    }

    private var filterPicker: some View {
        Picker(String(localized: "wardrobe.filter", bundle: .module), selection: $filter) {
            ForEach(CategoryFilter.allCases, id: \.self) { option in
                Text(option.title, bundle: .module).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, Spacing.lg)
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: Spacing.md) {
                ForEach(filteredItems) { item in
                    WardrobeItemCellView(item: item)
                }
            }
            .padding(Spacing.lg)
        }
    }

    /// `itemIdentifier` is the picker's own stable id. `data.hashValue` is not:
    /// Swift seeds hashing per process, so it never matches after a relaunch.
    private func scan(_ pickerItems: [PhotosPickerItem]) async {
        guard !pickerItems.isEmpty else { return }

        var photos: [(id: String, data: Data)] = []
        for item in pickerItems {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            photos.append((id: item.itemIdentifier ?? UUID().uuidString, data: data))
        }
        await viewModel.process(photos)
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
