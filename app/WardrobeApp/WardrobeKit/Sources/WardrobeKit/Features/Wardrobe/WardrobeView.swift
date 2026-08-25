import DesignSystem
import SwiftUI

public struct WardrobeView: View {
    @State private var isBulkScanPresented = false
    @State private var isCameraScanPresented = false
    @State private var isConflictsPresented = false

    @State private var viewModel: WardrobeViewModel
    @State private var expandedCategory: GarmentCategory?
    @State private var navigationPath = NavigationPath()
    @State private var isSearching = false
    @Namespace private var pileNamespace

    private let container: AppContainer

    public init(viewModel: WardrobeViewModel, container: AppContainer) {
        _viewModel = State(wrappedValue: viewModel)
        self.container = container
    }

    public var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                VStack(spacing: 0) {
                    topBar

                    ZStack {
                        Group {
                            if viewModel.isShowingSearchResults {
                                WardrobeSearchResultsView(
                                    items: viewModel.searchResults,
                                    thumbnailData: { viewModel.thumbnailData(for: $0) },
                                    wearCount: { viewModel.wearCount(for: $0) },
                                    onSelect: { navigationPath.append($0.id) }
                                )
                            } else if case .failed = viewModel.state {
                                failedState
                            } else if viewModel.items.isEmpty {
                                emptyState
                            } else if expandedCategory == nil {
                                pilesContent
                            } else {
                                Color.clear
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                        if let category = expandedCategory, !viewModel.isShowingSearchResults {
                            CategoryGridView(
                                category: category,
                                items: viewModel.items(in: category),
                                thumbnailData: { viewModel.thumbnailData(for: $0) },
                                wearCount: { viewModel.wearCount(for: $0) },
                                namespace: pileNamespace,
                                onClose: { close() },
                                onSelect: { navigationPath.append($0.id) },
                                sortOrder: $viewModel.sortOrder
                            )
                        }
                    }
                }
            }
            .appBackgroundStickers()
            .onTapGesture {
                #if os(iOS)
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
                    )
                #endif

                if viewModel.searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                    isSearching = false
                }
            }
            .navigationDestination(for: UUID.self) { itemID in
                WardrobeItemDetailView(
                    viewModel: container.makeWardrobeItemDetailViewModel(itemID: itemID)
                )
                .onDisappear { viewModel.load() }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                if viewModel.openConflictCount > 0 {
                    ConflictsBannerView(count: viewModel.openConflictCount) {
                        isConflictsPresented = true
                    }
                }
                if viewModel.pendingSyncCount + viewModel.failedSyncCount > 0 {
                    WardrobeSyncBannerView(
                        pending: viewModel.pendingSyncCount,
                        failed: viewModel.failedSyncCount,
                        onRetry: { viewModel.retryFailedSync() }
                    )
                }
            }
        }
        .sheet(
            isPresented: $isConflictsPresented,
            onDismiss: { viewModel.load() },
            content: { ConflictsView(viewModel: container.makeConflictsViewModel()) }
        )
        .task(id: container.contentRevision.revision) { viewModel.load() }
    }

    private var topBar: some View {
        HStack {
            WardrobeSearchBarView(query: $viewModel.searchQuery, isActive: $isSearching)

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
                HStack {
                    if !isSearching {
                        Text("wardrobe.add.title", bundle: .module)
                    }
                    Image(systemName: "plus.app")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 20, height: 20)
                }
                .font(AppFont.roundedTitle2)
                .fontWeight(.semibold)
                .foregroundStyle(AppColor.textPrimary)
                .padding(.vertical, Spacing.sm)
                .padding(.horizontal, isSearching ? Spacing.sm : Spacing.md)
                .background(Capsule()
                    .fill(.clear)
                    .glassEffect(.clear))
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
                AddByCameraView(viewModel: container.makeAddByCameraViewModel())
            }
        )
    }

    private func close() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
            expandedCategory = nil
        }
    }

    private var failedState: some View {
        ContentUnavailableView {
            Label {
                Text("wardrobe.failed.title", bundle: .module)
            } icon: {
                Image(systemName: "exclamationmark.triangle")
            }
        } description: {
            Text("wardrobe.failed.message", bundle: .module)
        } actions: {
            Button { viewModel.load() } label: { Text("common.retry", bundle: .module) }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label {
                Text("wardrobe.empty.title", bundle: .module)
            } icon: {
                Image("WardrobeEmpty", bundle: .module)
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
                    items: viewModel.items(in: .top),
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
                    items: viewModel.items(in: .bottom),
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

#Preview {
    let container = AppContainer()
    WardrobeView(viewModel: container.makeWardrobeViewModel(), container: container)
}
