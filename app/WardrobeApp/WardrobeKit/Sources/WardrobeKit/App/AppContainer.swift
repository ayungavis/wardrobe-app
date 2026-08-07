import Foundation

/// Composition root. Owns dependency construction so views and view models
/// stay injectable and testable.
@MainActor
public final class AppContainer {
    private let challengeRepository: ChallengeRepository

    public init(challengeRepository: ChallengeRepository = MockChallengeRepository()) {
        self.challengeRepository = challengeRepository
    }

    public func makeChallengeViewModel() -> ChallengeViewModel {
        ChallengeViewModel(repository: challengeRepository)
    }
}
