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
                Image("appBG", bundle: .module)
                    .resizable()
                    .ignoresSafeArea()

                if viewModel.completions.isEmpty {
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
                                        photoData: viewModel.photoData(for: completion)
                                    )
                                }
                                .rotationEffect(.degrees(-3))
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(Spacing.lg)
                    }
                }
            }
            .navigationTitle(Text("tab.history", bundle: .module))
            .navigationDestination(for: UUID.self) { completionID in
                if let completion = viewModel.completions.first(where: { $0.id == completionID }) {
                    HistoryDetailView(
                        completion: completion,
                        photoData: viewModel.photoData(for: completion),
                        viewModel: viewModel
                    )
                }
            }
        }
        .task { viewModel.load() }
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
