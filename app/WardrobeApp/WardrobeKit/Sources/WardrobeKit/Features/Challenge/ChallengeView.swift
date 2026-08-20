import DesignSystem
import SwiftUI
import Lottie

public struct ChallengeView: View {
    @State private var viewModel: ChallengeViewModel
    @State private var isDevMenuPresented = DevMode.opensOnLaunch
    @State private var hasSwiped = false
    
    private let container: AppContainer
    
    private let backgroundStickers: [StickerPlacement] = [
        StickerPlacement(
            "StampElement",
            figmaX: 284,
            figmaY: 56,
            figmaWidth: 142,
            figmaHeight: 162,
            frameWidth: 375,
            frameHeight: 812
        ),
        StickerPlacement(
            "StampDetail",
            figmaX: 38,
            figmaY: 752,
            figmaWidth: 104,
            figmaHeight: 120,
            frameWidth: 375,
            frameHeight: 812
        ),
        StickerPlacement(
            "Kancing2",
            figmaX: -18,
            figmaY: 257,
            figmaWidth: 104,
            figmaHeight: 120,
            frameWidth: 375,
            frameHeight: 812
        ),
    ]
    
    public init(viewModel: ChallengeViewModel, container: AppContainer) {
        _viewModel = State(wrappedValue: viewModel)
        self.container = container
    }
    
    public var body: some View {
        @Bindable var viewModel = viewModel
        
        NavigationStack {
            ZStack {
                Image("appBG", bundle: .module)
                    .resizable()
                    .ignoresSafeArea()
                
                GeometryReader { screenGeo in
                    let sw = screenGeo.size.width
                    let sh = screenGeo.size.height
                    
                    ForEach(backgroundStickers) { sticker in
                        Image(sticker.imageName, bundle: .module)
                            .resizable()
                            .scaledToFit()
                            .frame(width: sw * sticker.widthFraction)
                            .rotationEffect(.degrees(sticker.rotation))
                            .position(x: sw * sticker.x, y: sh * sticker.y)
                    }
                }
                
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
                //lottie animation here
                if !hasSwiped && !viewModel.hasCompletedToday && viewModel.activeChallenge == nil {
                    ZStack {
                        Color(AppColor.surface.opacity(0.1))
                        LottieView(animation: .named("HandSwipeAnimation", bundle: .module))
                            .playbackMode(.playing(.fromFrame(40, toFrame: 120, loopMode: .autoReverse)))
                            .resizable()
                            .frame(width: 300, height: 300)
                            .allowsHitTesting(false)
                            .offset(y: 280) // position over cards
                            .transition(.opacity)
                    }
                    
                }
            }
            // interaction listener
            .simultaneousGesture(
                DragGesture().onChanged { _ in
                    if !hasSwiped {
                        withAnimation(.easeOut(duration: 0.3)) {
                            hasSwiped = true
                        }
                    }
                }
            )
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 1).onEnded { _ in
                    isDevMenuPresented = true
                },
                including: DevMode.isEnabled ? .all : .none
            )
            
        
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
                        makeEditorViewModel: { container.makeEditorViewModel(challenge: $0) },
                        makeCropViewModel: { container.makeCropViewModel(photoID: $0) }
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
    ChallengeDeckView(cards: cards) { card in
        viewModel.accept(card)
    }
    .padding(.horizontal, Spacing.xl)
}
}

#Preview {
    let container = AppContainer()
    let _ = FontRegistration.registerCustomFonts()
    ChallengeView(
        viewModel: container.makeChallengeViewModel(),
        container: container
    )
}
