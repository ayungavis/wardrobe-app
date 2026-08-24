import DesignSystem
import SwiftUI

public struct RootView: View {
    private let container: AppContainer

    public init(container: AppContainer) {
        self.container = container
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
    }

    private var tabs: some View {
        TabView {
            Tab {
                ZStack {}
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

#Preview {
    RootView(container: AppContainer())
}
