import Foundation
import Observation

@MainActor
@Observable
public final class ChallengeViewModel {
    public private(set) var deck: Loadable<[ChallengeCard]> = .idle
    public private(set) var isShowingCuratedDeck = false
    public private(set) var activeChallenge: ActiveChallenge?
    public private(set) var hasCompletedToday = false
    public var isCaptureFlowPresented = false
    public var isAbandonConfirmationPresented = false

    private let challengeRepository: ChallengeRepository
    private let activeRepository: ActiveChallengeRepository
    private let completedRepository: CompletedChallengeRepository
    private let photoRepository: PhotoRepository
    private let wardrobeRepository: (any WardrobeItemRepository)?
    private let thumbnails: (any GarmentThumbnailRepository)?
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private(set) var garments: [UUID: CardGarments] = [:]
    private(set) var deckDay: Date?
    private(set) var loadTask: Task<Void, Never>?

    public init(
        challengeRepository: ChallengeRepository,
        activeRepository: ActiveChallengeRepository,
        completedRepository: CompletedChallengeRepository,
        photoRepository: PhotoRepository,
        wardrobeRepository: (any WardrobeItemRepository)? = nil,
        thumbnails: (any GarmentThumbnailRepository)? = nil,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.challengeRepository = challengeRepository
        self.activeRepository = activeRepository
        self.completedRepository = completedRepository
        self.photoRepository = photoRepository
        self.wardrobeRepository = wardrobeRepository
        self.thumbnails = thumbnails
        self.calendar = calendar
        self.now = now
    }

    public func onAppear() {
        refreshActiveChallenge()
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-autoResume"), activeChallenge != nil {
                isCaptureFlowPresented = true
            }
        #endif
        refreshForForeground()
    }

    public func refreshForForeground() {
        refreshActiveChallenge()
        resolveGarments()
        guard deckDay != calendar.startOfDay(for: now()) else { return }
        load()
    }

    public func reloadDeck() {
        deckDay = nil
        load()
    }

    public func load() {
        loadTask?.cancel()
        if case .loaded = deck {} else {
            deck = .loading
        }

        loadTask = Task {
            do {
                let daily = try await challengeRepository.fetchDailyDeck()
                try Task.checkCancellation()
                deck = .loaded(daily.cards)
                isShowingCuratedDeck = daily.isCurated
                // ponytail: a curated deck pins no day, so the real one is
                // retried on the next foreground; a good deck is not refetched
                // all day. Upgrade path is a timer at local midnight.
                deckDay = daily.isCurated ? nil : calendar.startOfDay(for: now())
                resolveGarments()
            } catch is CancellationError {
            } catch {
                Log.report(error, logger: Log.network)
                deck = .failed(AppError(wrapping: error))
            }
        }
    }

    public func garments(for card: ChallengeCard) -> CardGarments {
        garments[card.id] ?? CardGarments()
    }

    func resolveGarments() {
        guard case let .loaded(cards) = deck else { return }
        guard let wardrobeRepository, let thumbnails else { return }
        guard cards.contains(where: { $0.outfit != nil }) else {
            garments = [:]
            return
        }

        let items = (try? wardrobeRepository.items()) ?? []
        let index = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        garments = cards.reduce(into: [:]) { resolved, card in
            guard let outfit = card.outfit else { return }
            resolved[card.id] = CardGarments(
                top: garment(index[outfit.top], thumbnails),
                bottom: garment(index[outfit.bottom], thumbnails)
            )
        }
    }

    private func garment(
        _ item: WardrobeItem?,
        _ thumbnails: any GarmentThumbnailRepository
    ) -> CardGarment? {
        guard let item, let data = GarmentImage.data(for: item, in: thumbnails) else { return nil }
        return CardGarment(data: data, name: item.name)
    }

    public func accept(_ card: ChallengeCard) {
        if hasCompletedToday, !card.isFreestyle {
            return
        }

        if let active = activeChallenge {
            if active.card.id == card.id {
                isCaptureFlowPresented = true
            }
            return
        }

        let challenge = ActiveChallenge(card: card, acceptedAt: now())
        activeRepository.save(challenge)
        activeChallenge = challenge
        isCaptureFlowPresented = true
        Log.ui.info("Challenge accepted: \(card.id.uuidString, privacy: .public)")
    }

    public func resume() {
        isCaptureFlowPresented = true
    }

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

    public func refreshActiveChallenge() {
        activeChallenge = activeRepository.load()
        hasCompletedToday = completedRepository.hasCompletion(on: now())
    }
}
