import Foundation

extension DevMenuViewModel {
    func generateDeck() {
        deckState = .loading
        pullTask?.cancel()
        pullTask = Task { [outboxRepository, coordinator] in
            do {
                let args = GenerateChallengeDeckArgsDTO(localDate: LocalDay.string(from: Date()))
                try outboxRepository.enqueue(
                    SyncMutation.generateChallengeDeck(args).queued(),
                    at: Date()
                )
                _ = await coordinator.reconcile(.mutationQueued)
                guard !Task.isCancelled else { return }
                deckState = .loaded("queued for \(args.localDate)")
                refresh()
            } catch {
                deckState = .failed(AppError(wrapping: error))
            }
        }
    }

    func fetchDeck() {
        deckState = .loading
        pullTask?.cancel()
        pullTask = Task { [client] in
            do {
                let deck = try await ServerChallengeRepository(client: client).fetchDailyDeck()
                guard !Task.isCancelled else { return }
                let outfits = deck.cards.count { $0.outfit != nil }
                deckState = .loaded(
                    "\(deck.cards.count) cards, \(outfits) with garments, \(deck.isCurated ? "curated" : "generated")"
                )
            } catch {
                deckState = .failed(AppError(wrapping: error))
            }
        }
    }
}
