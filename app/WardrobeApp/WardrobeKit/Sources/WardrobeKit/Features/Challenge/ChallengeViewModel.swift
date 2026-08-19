import Foundation
import Observation

@MainActor
@Observable
public final class ChallengeViewModel {
    public private(set) var deck: Loadable<[ChallengeCard]> = .idle
    public private(set) var activeChallenge: ActiveChallenge?
    /// FR-012: one completed challenge per user-local calendar day.
    public private(set) var hasCompletedToday = false
    public var isCaptureFlowPresented = false
    public var isAbandonConfirmationPresented = false

    private let challengeRepository: ChallengeRepository
    private let activeRepository: ActiveChallengeRepository
    private let completedRepository: CompletedChallengeRepository
    private let photoRepository: PhotoRepository
    private(set) var loadTask: Task<Void, Never>?

    public init(
        challengeRepository: ChallengeRepository,
        activeRepository: ActiveChallengeRepository,
        completedRepository: CompletedChallengeRepository,
        photoRepository: PhotoRepository
    ) {
        self.challengeRepository = challengeRepository
        self.activeRepository = activeRepository
        self.completedRepository = completedRepository
        self.photoRepository = photoRepository
    }

    public func onAppear() {
        activeChallenge = activeRepository.load()
        hasCompletedToday = completedRepository.hasCompletion(on: Date())
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
                let cards = try await challengeRepository.fetchDailyDeck()
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
        guard !hasCompletedToday else { return } // deck is closed until reset

        if let active = activeChallenge {
            if active.card.id == card.id {
                isCaptureFlowPresented = true
            }
            return
        }

        let challenge = ActiveChallenge(card: card, acceptedAt: Date())
        activeRepository.save(challenge)
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
        if let active = activeChallenge {
            photoRepository.deleteOriginals(of: active.document, and: active.photoID)
        }
        activeRepository.clear()
        activeChallenge = nil
        Log.ui.info("Challenge abandoned")
    }

    /// The capture flow mutates both stores (photo, draft, completion) —
    /// re-read them when its cover closes.
    public func refreshActiveChallenge() {
        activeChallenge = activeRepository.load()
        hasCompletedToday = completedRepository.hasCompletion(on: Date())
    }
}
