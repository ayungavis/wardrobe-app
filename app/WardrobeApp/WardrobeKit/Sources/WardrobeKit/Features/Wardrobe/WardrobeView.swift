import DesignSystem
import SwiftUI

public struct WardrobeView: View {
    @State private var isBulkScanPresented = false
    @State private var isCameraScanPresented = false

    @State private var viewModel: WardrobeViewModel
    @State private var expandedCategory: GarmentCategory?
    @State private var navigationPath = NavigationPath()
    @State private var sortOrder: SortOrder = .mostUsed
    @Namespace private var pileNamespace

    private let container: AppContainer

    public init(viewModel: WardrobeViewModel, container: AppContainer) {
        _viewModel = State(wrappedValue: viewModel)
        self.container = container
    }

    private var topItems: [WardrobeItem] { viewModel.items.filter { $0.category == .top } }
    private var bottomItems: [WardrobeItem] { viewModel.items.filter { $0.category == .bottom } }

    public var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                Image("appBG", bundle: .module)
                    .resizable()
                    .ignoresSafeArea()

                // Single top-to-bottom layout: bar, then content below it —
                // nothing floats independently anymore.
                VStack(spacing: 0) {
                    topBar

                    ZStack {
                        Group {
                            if viewModel.items.isEmpty {
                                emptyState
                            } else if expandedCategory == nil {
                                pilesContent
                            } else {
                                Color.clear
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                        if let category = expandedCategory {
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
            .navigationDestination(for: UUID.self) { itemID in
                WardrobeItemDetailView(
                    viewModel: container.makeWardrobeItemDetailViewModel(itemID: itemID),
                    onDeleted: { viewModel.load() }
                )
            }
        }
        .task { viewModel.load() }
    }

    private var topBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .resizable()
                .scaledToFill()
                .frame(width: 20, height: 20)
                .padding(Spacing.md)
                .background(Capsule().fill(.ultraThinMaterial))

            Spacer()

            Menu {
                Button {
                    isCameraScanPresented = true
                } label: {
                    Label("Camera", systemImage: "camera")
                }
                Button {
                    isBulkScanPresented = true
                } label: {
                    Label("Add from Photos", systemImage: "photo.on.rectangle")
                }
            } label: {
                Image(systemName: "plus")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 20, height: 20)
                    .padding(Spacing.md)
                    .background(Capsule().fill(.ultraThinMaterial))
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.top, Spacing.md)
        .sheet(isPresented: $isBulkScanPresented) {
            BulkScanView(review: container.makeGarmentReviewModel())
        }
        .sheet(isPresented: $isCameraScanPresented) {
            BulkScanCameraView(camera: container.makeCameraService(), review: container.makeGarmentReviewModel())
        }
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
                Image(systemName: "tshirt")
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
                    namespace: pileNamespace
                ) {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                        expandedCategory = .top
                    }
                }
                PileCardView(
                    category: .bottom,
                    items: bottomItems,
                    thumbnailData: { viewModel.thumbnailData(for: $0) },
                    namespace: pileNamespace
                ) {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                        expandedCategory = .bottom
                    }
                }
            }
            .padding(Spacing.lg)
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
