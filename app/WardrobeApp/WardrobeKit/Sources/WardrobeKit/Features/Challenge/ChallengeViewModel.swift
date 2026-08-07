import Foundation
import Observation

public struct ChallengeCard: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let prompt: String

    public init(id: UUID = UUID(), prompt: String) {
        self.id = id
        self.prompt = prompt
    }
}

public protocol ChallengeRepository: Sendable {
    func fetchDailyDeck() async throws -> [ChallengeCard]
}

// ponytail: mock deck until the backend exists; replace with the API-backed
// repository once services/ ships its first endpoint.
public struct MockChallengeRepository: ChallengeRepository {
    public init() {}

    public func fetchDailyDeck() async throws -> [ChallengeCard] {
        [
            ChallengeCard(prompt: "Today is a good day to wear something red."),
            ChallengeCard(prompt: "Style your most comfortable shoes for going out."),
            ChallengeCard(prompt: "Layer two pieces you have never worn together."),
        ]
    }
}

@MainActor
@Observable
public final class ChallengeViewModel {
    public private(set) var deck: Loadable<[ChallengeCard]> = .idle

    private let repository: ChallengeRepository
    private(set) var loadTask: Task<Void, Never>?

    public init(repository: ChallengeRepository) {
        self.repository = repository
    }

    public func onAppear() {
        guard case .idle = deck else { return }
        load()
    }

    public func load() {
        loadTask?.cancel()
        deck = .loading

        loadTask = Task {
            do {
                let cards = try await repository.fetchDailyDeck()
                try Task.checkCancellation()
                deck = .loaded(cards)
            } catch is CancellationError {
                // Ignore cancellation.
            } catch {
                Log.report(error, logger: Log.network)
                deck = .failed(AppError(wrapping: error))
            }
        }
    }

    public func accept(_ card: ChallengeCard) {
        // TODO: persist active challenge (FR-011) once the challenge lifecycle lands.
        Log.ui.info("Challenge accepted: \(card.id.uuidString, privacy: .public)")
    }
}
