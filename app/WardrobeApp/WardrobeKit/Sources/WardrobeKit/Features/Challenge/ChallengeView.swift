import DesignSystem
import SwiftUI

public struct ChallengeView: View {
    @State private var viewModel: ChallengeViewModel

    public init(viewModel: ChallengeViewModel) {
        _viewModel = State(wrappedValue: viewModel)
    }

    public var body: some View {
        NavigationStack {
            Group {
                switch viewModel.deck {
                case .idle, .loading:
                    ProgressView()
                case let .failed(error):
                    errorView(error)
                case let .loaded(cards):
                    deckView(cards)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppColor.background)
            .navigationTitle(Text("tab.challenge", bundle: .module))
        }
        .task { viewModel.onAppear() }
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

struct ChallengeCardView: View {
    let card: ChallengeCard
    let onAccept: () -> Void

    var body: some View {
        VStack(spacing: Spacing.xl) {
            Text(card.prompt)
                .font(AppFont.title)
                .foregroundStyle(AppColor.textPrimary)
                .multilineTextAlignment(.center)

            PrimaryButton(Text("challenge.accept", bundle: .module), action: onAccept)
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity)
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 16))
        .appShadow(.card)
    }
}

#Preview {
    ChallengeView(viewModel: ChallengeViewModel(repository: MockChallengeRepository()))
}
