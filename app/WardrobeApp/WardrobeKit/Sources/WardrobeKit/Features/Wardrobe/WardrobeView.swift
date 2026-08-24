import DesignSystem
import SwiftUI

public struct WardrobeView: View {
    @State private var isBulkScanPresented = false
    @State private var isCameraScanPresented = false

    @State private var viewModel: WardrobeViewModel
    @State private var expandedCategory: GarmentCategory?
    @State private var navigationPath = NavigationPath()
    @State private var sortOrder: SortOrder = .mostUsed
    @State private var searchQuery = ""
    @State private var isSearching = false
    @Namespace private var pileNamespace

    private let container: AppContainer

    public init(viewModel: WardrobeViewModel, container: AppContainer) {
        _viewModel = State(wrappedValue: viewModel)
        self.container = container
    }

    private var searchResults: [WardrobeItem] {
        WardrobeSearch.results(in: viewModel.items, matching: searchQuery)
    }

    private var isShowingSearchResults: Bool {
        isSearching && !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var topItems: [WardrobeItem] {
        viewModel.items.filter { $0.category == .top }
    }

    private var bottomItems: [WardrobeItem] {
        viewModel.items.filter { $0.category == .bottom }
    }

    public var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
//                Image("appBG", bundle: .module)
//                    .resizable()
//                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    topBar

                    ZStack {
                        Group {
                            if isShowingSearchResults {
                                WardrobeSearchResultsView(
                                    items: searchResults,
                                    thumbnailData: { viewModel.thumbnailData(for: $0) },
                                    wearCount: { viewModel.wearCount(for: $0) },
                                    onSelect: { navigationPath.append($0.id) }
                                )
                            } else if viewModel.items.isEmpty {
                                emptyState
                            } else if expandedCategory == nil {
                                pilesContent
                            } else {
                                Color.clear
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                        if let category = expandedCategory, !isShowingSearchResults {
                            CategoryGridView(
                                category: category,
                                items: category == .top ? topItems : bottomItems,
                                thumbnailData: { viewModel.thumbnailData(for: $0) },
                                wearCount: { viewModel.wearCount(for: $0) },
                                namespace: pileNamespace,
                                onClose: { close() },
                                onSelect: { navigationPath.append($0.id) },
                                sortOrder: $sortOrder
                            )
                        }
                    }
                }
            }
            .appBackgroundStickers()
            .navigationDestination(for: UUID.self) { itemID in
                WardrobeItemDetailView(
                    viewModel: container.makeWardrobeItemDetailViewModel(itemID: itemID)
                )
                .onDisappear { viewModel.load() }
            }
        }
        .task { viewModel.load() }
    }

    private var topBar: some View {
        HStack {
            WardrobeSearchBarView(query: $searchQuery, isActive: $isSearching)

            if !isSearching {
                Spacer()
            }

            Menu {
                Button {
                    isCameraScanPresented = true
                } label: {
                    Label { Text("wardrobe.add.camera", bundle: .module) } icon: { Image(systemName: "camera") }
                }
                Button {
                    isBulkScanPresented = true
                } label: {
                    Label { Text("wardrobe.add.photos", bundle: .module) } icon: { Image(systemName: "photo.on.rectangle") }
                }
            } label: {
                HStack{
                    Text("wardrobe.add.title", bundle: .module)
                    Image(systemName: "plus.app")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 20, height: 20)
                }
                .font(AppFont.roundedTitle2)
                .fontWeight(.semibold)
                .foregroundStyle(AppColor.textPrimary)
                .padding(.vertical, Spacing.sm)
                .padding(.horizontal, Spacing.md)
                .background(Capsule()
                    //.fill(AppColor.surface)
                    .fill(.clear)
                    .glassEffect(.clear)
                )
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.top, Spacing.md)
        .animation(.snappy, value: isSearching)
        .onChange(of: isSearching) { _, searching in
            if searching {
                expandedCategory = nil
            }
        }
        .sheet(
            isPresented: $isBulkScanPresented,
            onDismiss: { viewModel.load() },
            content: { AddByPhotosView(review: container.makeGarmentReviewModel()) }
        )
        .sheet(
            isPresented: $isCameraScanPresented,
            onDismiss: { viewModel.load() },
            content: {
                AddByCameraView(
                    camera: container.makeCameraService(),
                    review: container.makeGarmentReviewModel()
                )
            }
        )
    }

    private func close() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
            expandedCategory = nil
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label {
                Text("wardrobe.empty.title", bundle: .module)
            } icon: {
                Image(systemName: "WardrobeEmpty")
            }
        } description: {
            Text("wardrobe.empty.message", bundle: .module)
        }
    }

    private var pilesContent: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                PileCardView(
                    category: .top,
                    items: topItems,
                    thumbnailData: { viewModel.thumbnailData(for: $0) },
                    namespace: pileNamespace,
                    onTap: {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                            expandedCategory = .top
                        }
                    }
                )
                PileCardView(
                    category: .bottom,
                    items: bottomItems,
                    thumbnailData: { viewModel.thumbnailData(for: $0) },
                    namespace: pileNamespace,
                    onTap: {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                            expandedCategory = .bottom
                        }
                    }
                )
            }
            .padding(Spacing.md)
        }
    }
}

extension WardrobeView {
    enum SortOrder: String, CaseIterable {
        case mostUsed
        case leastUsed

        var title: LocalizedStringKey {
            switch self {
            case .mostUsed: "wardrobe.sort.mostUsed"
            case .leastUsed: "wardrobe.sort.leastUsed"
            }
        }
    }
}

#Preview {
    let container = AppContainer()
    WardrobeView(viewModel: container.makeWardrobeViewModel(), container: container)
}
