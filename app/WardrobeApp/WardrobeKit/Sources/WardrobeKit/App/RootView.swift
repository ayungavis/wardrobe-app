import DesignSystem
import SwiftUI

public struct RootView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    private let container: AppContainer

    public init(container: AppContainer) {
        self.container = container
    }

    public var body: some View {
        ZStack{
            Image("appBG")
                .resizable()
                .ignoresSafeArea()
            if hasCompletedOnboarding {
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
                .toolbarBackground(.hidden, for: .tabBar)
                .background(.clear)
                
                
            } else {
                WelcomeView {
                    hasCompletedOnboarding = true
                }
                
            }
        }
    }
}

#Preview {
    RootView(container: AppContainer())

}
