import DesignSystem
import SwiftUI

public struct RootView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    private let container: AppContainer

    public init(container: AppContainer) {
        self.container = container
    }

    public var body: some View {
        if hasCompletedOnboarding {
            TabView {
                Tab {
                    ChallengeView(viewModel: container.makeChallengeViewModel())
                } label: {
                    Label {
                        Text("tab.challenge", bundle: .module)
                    } icon: {
                        Image(systemName: "sparkles")
                    }
                }

                Tab {
                    WardrobeView()
                } label: {
                    Label {
                        Text("tab.wardrobe", bundle: .module)
                    } icon: {
                        Image(systemName: "tshirt")
                    }
                }

                Tab {
                    HistoryView()
                } label: {
                    Label {
                        Text("tab.history", bundle: .module)
                    } icon: {
                        Image(systemName: "photo.on.rectangle.angled")
                    }
                }
            }
        } else {
            WelcomeView {
                hasCompletedOnboarding = true
            }
        }
    }
}

#Preview {
    RootView(container: AppContainer())
}
