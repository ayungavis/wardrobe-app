import Foundation

public protocol ChallengeRepository: Sendable {
    func fetchDailyDeck() async throws -> DailyDeck
}

// ponytail: the curated catalog is the permanent fallback (FR-008), not a
// stand-in to delete once the backend exists. Its ids mirror
// migrations/0009_curated_cards.sql and 0013_challenge_text_capability.sql.
public struct CuratedChallengeRepository: ChallengeRepository {
    public init() {}

    public static let deck: [ChallengeCard] = [
        card("019205f0-0000-7000-8000-000000000002", "Seeing red",
             "Today is a good day to wear something red."),
        card("019205f0-0000-7000-8000-000000000003", "Comfort out",
             "Style your most comfortable shoes for going out."),
        card("019205f0-0000-7000-8000-000000000004", "Never paired",
             "Layer two pieces you have never worn together."),
        card("019205f0-0000-7000-8000-000000000005", "One colour only",
             "Build a whole outfit around a single colour."),
        card("019205f0-0000-7000-8000-000000000006", "Back of the rail",
             "Wear the piece that has hung at the back the longest."),
    ]

    public func fetchDailyDeck() async throws -> DailyDeck {
        DailyDeck(cards: Self.deck, isCurated: true)
    }

    private static func card(_ literal: String, _ title: String, _ prompt: String) -> ChallengeCard {
        // Type safety: compile-time-constant UUID literals mirroring the seeded
        // catalog; a typo fails the catalog test before it can break a foreign key.
        // swiftlint:disable:next force_unwrapping
        ChallengeCard(id: UUID(uuidString: literal)!, title: title, prompt: prompt)
    }
}

public struct ServerChallengeRepository: ChallengeRepository {
    private let client: any AuthenticatedAPIClient
    private let timeZone: TimeZone
    private let now: @Sendable () -> Date

    public init(
        client: any AuthenticatedAPIClient,
        timeZone: TimeZone = .current,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.client = client
        self.timeZone = timeZone
        self.now = now
    }

    public func fetchDailyDeck() async throws -> DailyDeck {
        let response = try await client.send(
            GetChallengesDeckEndpoint(
                localDate: LocalDay.string(from: now(), timeZone: timeZone),
                locale: Locale.current.identifier
            )
        )
        return DailyDeck(
            cards: response.cards.map { card in
                ChallengeCard(
                    id: card.id,
                    title: card.title,
                    prompt: card.prompt,
                    topItemID: card.topItemId,
                    bottomItemID: card.bottomItemId
                )
            },
            isCurated: response.source != "generated"
        )
    }
}

public struct FallbackChallengeRepository: ChallengeRepository {
    private let primary: any ChallengeRepository
    private let fallback: any ChallengeRepository

    public init(primary: any ChallengeRepository, fallback: any ChallengeRepository) {
        self.primary = primary
        self.fallback = fallback
    }

    public func fetchDailyDeck() async throws -> DailyDeck {
        do {
            let deck = try await primary.fetchDailyDeck()
            guard deck.cards.isEmpty else { return deck }
            return try await fallback.fetchDailyDeck()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            Log.report(error, logger: Log.network)
            return try await fallback.fetchDailyDeck()
        }
    }
}
