import DesignSystem
import SwiftUI

public struct RootView: View {
    /// FR-002: onboarding completion is an account preference, so it lives in
    /// the preferences record rather than a standalone key — that is what stops
    /// a second phone from replaying onboarding once the record syncs.
    @State private var hasCompletedOnboarding: Bool

    private let container: AppContainer

    public init(container: AppContainer) {
        self.container = container
        _hasCompletedOnboarding = State(
            initialValue: container.preferencesRepository.load().hasCompletedOnboarding
        )
    }

    public var body: some View {
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
                completeOnboarding()
            }
        }
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
