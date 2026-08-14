import DesignSystem
import SwiftUI

public struct ChallengeView: View {
    @State private var viewModel: ChallengeViewModel
    @State private var isDevMenuPresented = DevMode.opensOnLaunch
    private let container: AppContainer

    public init(viewModel: ChallengeViewModel, container: AppContainer) {
        _viewModel = State(wrappedValue: viewModel)
        self.container = container
    }

    public var body: some View {
        @Bindable var viewModel = viewModel

        NavigationStack {
            Group {
                if viewModel.hasCompletedToday {
                    CompletedTodayView()
                } else if let active = viewModel.activeChallenge {
                    ActiveChallengeStateView(
                        challenge: active,
                        onResume: { viewModel.resume() },
                        onAbandon: { viewModel.requestAbandon() }
                    )
                } else {
                    deckContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppColor.background)
            .navigationTitle(Text("tab.challenge", bundle: .module))
            // Long-press anywhere on this screen opens the dev menu. `including:`
            // reads a process constant, so view identity never changes.
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 1).onEnded { _ in
                    isDevMenuPresented = true
                },
                including: DevMode.isEnabled ? .all : .none
            )
            .sheet(
                isPresented: $isDevMenuPresented,
                onDismiss: { viewModel.refreshActiveChallenge() },
                content: {
                    DevMenuView(
                        viewModel: container.makeDevMenuViewModel(),
                        makeReview: { container.makeGarmentReviewModel() },
                        makeBenchmark: { container.makeMatchBenchmarkViewModel() },
                        onStateChanged: { viewModel.refreshActiveChallenge() }
                    )
                }
            )
        }
        .task { viewModel.onAppear() }
        .confirmationDialog(
            Text("challenge.abandon.confirm.title", bundle: .module),
            isPresented: $viewModel.isAbandonConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                viewModel.abandon()
            } label: {
                Text("challenge.abandon.confirm.action", bundle: .module)
            }
            Button(role: .cancel) {} label: {
                Text("common.cancel", bundle: .module)
            }
        } message: {
            Text("challenge.abandon.confirm.message", bundle: .module)
        }
        #if os(iOS)
        .fullScreenCover(
            isPresented: $viewModel.isCaptureFlowPresented,
            onDismiss: { viewModel.refreshActiveChallenge() },
            content: {
                if let active = viewModel.activeChallenge {
                    CaptureFlowView(
                        viewModel: container.makeCaptureFlowViewModel(challenge: active),
                        makeEditorViewModel: { container.makeEditorViewModel(challenge: $0) }
                    )
                }
            }
        )
        #endif
    }

    @ViewBuilder
    private var deckContent: some View {
        switch viewModel.deck {
        case .idle, .loading:
            ProgressView()
        case let .failed(error):
            errorView(error)
        case let .loaded(cards):
            deckView(cards)
        }
    }

    private func errorView(_ error: AppError) -> some View {
        ContentUnavailableView {
            Label {
                Text("challenge.error.title", bundle: .module)
            } icon: {
                Image(systemName: "wifi.exclamationmark")
            }
        } description: {
            Text(error.userMessage)
        } actions: {
            Button {
                viewModel.load()
            } label: {
                Text("common.retry", bundle: .module)
            }
        }
    }

    private func deckView(_ cards: [ChallengeCard]) -> some View {
        // ponytail: paged TabView as the stacked-carousel stand-in; revisit
        // when the real card-deck design lands (FR-007 also needs non-swipe
        // browsing buttons for VoiceOver).
        TabView {
            ForEach(cards) { card in
                ChallengeCardView(card: card) {
                    viewModel.accept(card)
                }
                .padding(.horizontal, Spacing.xl)
            }
        }
        #if os(iOS)
        .tabViewStyle(.page)
        #endif
    }
}
