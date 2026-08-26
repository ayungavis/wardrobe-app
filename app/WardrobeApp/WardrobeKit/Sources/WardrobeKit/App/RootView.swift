import DesignSystem
import SwiftUI

public struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var challenge: ChallengeViewModel
    @State private var tab: RootTab = .challenge
    @State private var isDevMenuPresented = DevMode.opensOnLaunch
    @State private var isConsentPresented = false

    private let container: AppContainer
    @State private var isShowingSplash = true

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
            if isShowingSplash {
                SplashScreenView {
                    withAnimation(.easeOut(duration: 0.3)) {
                        isShowingSplash = false
                    }
                }
                .transition(.opacity)
                .zIndex(10)
            }
        }
        .preferredColorScheme(.light)
        .task {
            container.startDiagnostics()
            await container.startSession()
            // ponytail: onChange(of: scenePhase) never fires for the initial value, and
            // when it does it can run before this context is queued. A cold launch would
            // then leave the zone sitting in the outbox and never get a deck.
            await container.weatherRepository.refresh(now: Date())
            await container.syncCoordinator.reconcile(.mutationQueued)
            container.reachability.observe {
                Task { await container.syncCoordinator.reconcile(.connectivityRestored) }
            }
        }
        // ponytail: a heartbeat rather than a push. It only reaches the network
        // while the server still owes an illustration; replace it the day push
        // notifications exist.
        .task {
            while !Task.isCancelled {
                let waiting = container.isAwaitingIllustration
                try? await Task.sleep(for: waiting ? .seconds(3) : .seconds(10))
                guard !Task.isCancelled, container.isAwaitingIllustration else { continue }
                _ = await container.syncCoordinator.reconcile(.manual)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            presentConsentIfNeeded()
            challenge.refreshForForeground()
            Task { await container.syncCoordinator.reconcile(.foreground) }
            Task { await container.weatherRepository.refresh(now: Date()) }
        }
        .onChange(of: container.onboarding.isSignedIn) { _, signedIn in
            guard signedIn else { return }
            Task { await container.syncCoordinator.reconcile(.signedIn) }
        }
        .onChange(of: tab) { _, opened in
            presentConsentIfNeeded()
            guard opened != .challenge else {
                challenge.refreshForForeground()
                return
            }
            Task { await container.syncCoordinator.reconcile(.tabOpened) }
        }
        // ponytail: only the Challenge screen is refreshed after a dev reset. Wardrobe
        // and History load in .task, which does not re-run on a tab switch, so a reset
        // made from those tabs reads stale until the tab is rebuilt. Give RootView
        // their view models too if that starts biting.
        .sheet(isPresented: $isConsentPresented) {
            ConsentView(viewModel: container.makeConsentViewModel()) {
                isConsentPresented = false
                Task { await container.syncCoordinator.reconcile(.manual) }
            }
        }
        .sheet(
            isPresented: $isDevMenuPresented,
            onDismiss: {
                challenge.refreshActiveChallenge()
                challenge.reloadDeck()
            },
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

    private func presentConsentIfNeeded() {
        guard !isConsentPresented, container.needsUploadConsentPrompt else { return }
        isConsentPresented = true
    }

    private var tabs: some View {
        TabView(selection: $tab) {
            Tab(value: RootTab.challenge) {
                ZStack {}
                ChallengeView(viewModel: challenge, container: container)

            } label: {
                Label {
                    Text("tab.challenge", bundle: .module)
                } icon: {
                    Image(systemName: "sparkles")
                }
            }

            Tab(value: RootTab.wardrobe) {
                WardrobeView(viewModel: container.makeWardrobeViewModel(), container: container)
            } label: {
                Label {
                    Text("tab.wardrobe", bundle: .module)
                } icon: {
                    Image(systemName: "tshirt")
                }
            }

            Tab(value: RootTab.history) {
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

enum RootTab: Hashable {
    case challenge
    case wardrobe
    case history
}

#Preview {
    RootView(container: AppContainer())
}
