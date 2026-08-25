import DesignSystem
import SwiftUI

public struct RootView: View {
    @State private var challenge: ChallengeViewModel
    @State private var isDevMenuPresented = DevMode.opensOnLaunch

    private let container: AppContainer

    public init(container: AppContainer) {
        self.container = container
        _challenge = State(wrappedValue: container.makeChallengeViewModel())
    }

    public var body: some View {
        ZStack {
            Image("appBG", bundle: .module)
                .resizable()
                .ignoresSafeArea()

            if container.onboarding.isCompleted {
                tabs
            } else {
                OnboardingView(viewModel: container.makeOnboardingViewModel())
            }
        }
        .preferredColorScheme(.light)
        .task { await container.startSession() }
        // ponytail: only the Challenge screen is refreshed after a dev reset. Wardrobe
        // and History load in .task, which does not re-run on a tab switch, so a reset
        // made from those tabs reads stale until the tab is rebuilt. Give RootView
        // their view models too if that starts biting.
        .sheet(
            isPresented: $isDevMenuPresented,
            onDismiss: { challenge.refreshActiveChallenge() },
            content: {
                DevMenuView(
                    viewModel: container.makeDevMenuViewModel(),
                    makeReview: { container.makeGarmentReviewModel() },
                    makeBenchmark: { container.makeMatchBenchmarkViewModel() },
                    onStateChanged: { challenge.refreshActiveChallenge() }
                )
            }
        )
        #if os(iOS)
        .background {
            if DevMode.isEnabled {
                ShakeDetectorView { isDevMenuPresented = true }
                    .frame(width: 0, height: 0)
            }
        }
        #endif
    }

    private var tabs: some View {
        TabView {
            Tab {
                ZStack {}
                ChallengeView(viewModel: challenge, container: container)

            } label: {
                Label {
                    Text("tab.challenge", bundle: .module)
                } icon: {
                    Image(systemName: "sparkles")
                }
            }

            Tab {
                WardrobeView(viewModel: container.makeWardrobeViewModel(), container: container)
            } label: {
                Label {
                    Text("tab.wardrobe", bundle: .module)
                } icon: {
                    Image(systemName: "tshirt")
                }
            }

            Tab {
                HistoryView(viewModel: container.makeHistoryViewModel(), container: container)
            } label: {
                Label {
                    Text("tab.history", bundle: .module)
                } icon: {
                    Image(systemName: "photo.on.rectangle.angled")
                }
            }
        }
        #if os(iOS)
        .toolbarBackground(.hidden, for: .tabBar)
        #endif
        .background(.clear)
    }
}

#Preview {
    RootView(container: AppContainer())
}
