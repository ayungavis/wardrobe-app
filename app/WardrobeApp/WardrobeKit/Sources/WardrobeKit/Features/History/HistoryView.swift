import DesignSystem
import SwiftUI

public struct HistoryView: View {
    @State private var viewModel: HistoryViewModel
    @State private var navigationPath = NavigationPath()
    private let container: AppContainer

    public init(viewModel: HistoryViewModel, container: AppContainer) {
        _viewModel = State(wrappedValue: viewModel)
        self.container = container
    }

    private let columns = [
        GridItem(.flexible(), spacing: Spacing.md),
        GridItem(.flexible(), spacing: Spacing.md),
    ]

    public var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                VStack {
                    header
                    if case .idle = viewModel.state {
                        ProgressView()
                    } else if viewModel.completions.isEmpty {
                        emptyState
                    } else {
                        ScrollView {
                            LazyVGrid(columns: columns, spacing: Spacing.md) {
                                ForEach(viewModel.completions) { completion in
                                    Button {
                                        navigationPath.append(completion.id)
                                    } label: {
                                        HistoryPolaroidCardView(
                                            completion: completion,
                                            previewData: viewModel.previewData(for: completion)
                                        )
                                        .task { await viewModel.renderMissingPreview(for: completion) }
                                    }
                                    .rotationEffect(.degrees(-3))
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(Spacing.lg)
                        }
                    }
                }
            }
            .appBackgroundStickers()
            .navigationDestination(for: UUID.self) { completionID in
                if let completion = viewModel.completion(id: completionID) {
                    HistoryDetailView(
                        completion: completion,
                        previewData: viewModel.previewData(for: completion),
                        viewModel: viewModel,
                        onSelectGarment: { garmentID in
                            navigationPath.append(GarmentRoute(id: garmentID))
                        }
                    )
                }
            }
            .navigationDestination(for: GarmentRoute.self) { route in
                WardrobeItemDetailView(
                    viewModel: container.makeWardrobeItemDetailViewModel(itemID: route.id)
                )
            }
        }
        .task { viewModel.load() }
    }

    private var header: some View {
        Text("tab.history", bundle: .module)
            .font(AppFont.roundedLargeTitle)
            .foregroundStyle(AppColor.textPrimary)
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.lg)
            .padding(.bottom, Spacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack {
            Text("history.empty.title", bundle: .module)
                .font(AppFont.title)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
        }
    }
}
