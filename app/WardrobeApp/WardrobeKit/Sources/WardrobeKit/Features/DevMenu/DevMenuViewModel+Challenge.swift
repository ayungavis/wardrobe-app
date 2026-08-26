import Foundation

extension DevMenuViewModel {
    func generateDeck() {
        deckState = .loading
        pullTask?.cancel()
        pullTask = Task { [outboxRepository, coordinator, client] in
            do {
                let deck = ServerChallengeRepository(client: client)
                let before = await Set((try? deck.fetchDailyDeck().cards.map(\.id)) ?? [])
                let args = GenerateChallengeDeckArgsDTO(localDate: LocalDay.string(from: Date()))
                try outboxRepository.enqueue(
                    SyncMutation.generateChallengeDeck(args).queued(),
                    at: Date()
                )
                _ = await coordinator.reconcile(.mutationQueued)
                guard !Task.isCancelled else { return }

                // ponytail: the worker polls on its own schedule, so the deck arrives after
                // this returns. Waiting for it keeps the readout honest; a push would
                // replace this the day one exists.
                for _ in 0 ..< Self.deckAttempts {
                    try await Task.sleep(for: .seconds(2))
                    guard !Task.isCancelled else { return }
                    let fresh = try await deck.fetchDailyDeck()
                    if Set(fresh.cards.map(\.id)) != before {
                        deckState = .loaded(Self.summary(fresh))
                        refresh()
                        return
                    }
                }
                deckState = .loaded("queued for \(args.localDate), still waiting on the worker")
                refresh()
            } catch {
                deckState = .failed(AppError(wrapping: error))
            }
        }
    }

    static let deckAttempts = 8

    static func summary(_ deck: DailyDeck) -> String {
        let outfits = deck.cards.count { $0.outfit != nil }
        return "\(deck.cards.count) cards, \(outfits) with garments, "
            + (deck.isCurated ? "curated" : "generated")
    }

    func fetchDeck() {
        deckState = .loading
        pullTask?.cancel()
        pullTask = Task { [client] in
            do {
                let deck = try await ServerChallengeRepository(client: client).fetchDailyDeck()
                guard !Task.isCancelled else { return }
                deckState = .loaded(Self.summary(deck))
            } catch {
                deckState = .failed(AppError(wrapping: error))
            }
        }
    }
}
