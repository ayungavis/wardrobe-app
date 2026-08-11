import Foundation
import Observation

public struct ChallengeCard: Identifiable, Equatable, Sendable, Codable {
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
    public private(set) var activeChallenge: ActiveChallenge?
    public var isCaptureFlowPresented = false
    public var isAbandonConfirmationPresented = false

    private let repository: ChallengeRepository
    private let store: ActiveChallengeStore
    private let photoStore: PhotoStore
    private(set) var loadTask: Task<Void, Never>?

    public init(repository: ChallengeRepository, store: ActiveChallengeStore, photoStore: PhotoStore) {
        self.repository = repository
        self.store = store
        self.photoStore = photoStore
    }

    public func onAppear() {
        activeChallenge = store.load()
        #if DEBUG
            // UI-verification seam: `-autoResume` opens the capture flow without a tap.
            if ProcessInfo.processInfo.arguments.contains("-autoResume"), activeChallenge != nil {
                isCaptureFlowPresented = true
            }
        #endif
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

    /// FR-011: explicit accept persists ONE active challenge; re-accepting the
    /// same card is idempotent; accepting another requires explicit abandon.
    public func accept(_ card: ChallengeCard) {
        if let active = activeChallenge {
            if active.card.id == card.id {
                isCaptureFlowPresented = true
            }
            return
        }

        let challenge = ActiveChallenge(card: card, acceptedAt: Date())
        store.save(challenge)
        activeChallenge = challenge
        isCaptureFlowPresented = true
        Log.ui.info("Challenge accepted: \(card.id.uuidString, privacy: .public)")
    }

    public func resume() {
        isCaptureFlowPresented = true
    }

    /// FR-017: confirm before discarding a photo or edits.
    public func requestAbandon() {
        guard let active = activeChallenge else { return }
        if active.hasDraftWork {
            isAbandonConfirmationPresented = true
        } else {
            abandon()
        }
    }

    public func abandon() {
        if let photoID = activeChallenge?.photoID {
            do {
                try photoStore.deleteOriginal(id: photoID)
            } catch {
                Log.report(error) // orphaned file is not worth blocking the abandon
            }
        }
        store.clear()
        activeChallenge = nil
        Log.ui.info("Challenge abandoned")
    }

    /// The capture flow mutates the store (photoID, draft) — re-read on dismiss.
    public func refreshActiveChallenge() {
        activeChallenge = store.load()
    }
}
