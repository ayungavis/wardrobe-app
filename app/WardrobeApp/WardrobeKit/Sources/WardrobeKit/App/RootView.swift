import DesignSystem
import SwiftUI

public struct RootView: View {
    @State private var hasCompletedOnboarding: Bool

    private let container: AppContainer

    public init(container: AppContainer) {
        self.container = container
        _hasCompletedOnboarding = State(
            initialValue: container.preferencesRepository.load().hasCompletedOnboarding
        )
    }

    public var body: some View {
        ZStack {
            Image("appBG", bundle: .module)
                .resizable()
                .ignoresSafeArea()

            if hasCompletedOnboarding {
                tabs
            } else {
                WelcomeView {
                    completeOnboarding()
                }
            }
        }
    }

    private var tabs: some View {
        TabView {
            Tab {
                ChallengeView(viewModel: container.makeChallengeViewModel(), container: container)
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

private extension RootView {
    func completeOnboarding() {
        var preferences = container.preferencesRepository.load()
        preferences.hasCompletedOnboarding = true
        container.preferencesRepository.save(preferences)
        hasCompletedOnboarding = true
    }
}

#Preview {
    RootView(container: AppContainer())
}
