import Foundation

/// A challenge the user committed with the checkmark (PRD FR-028).
///
/// Wear records and confirmed wardrobe items (FR-029) arrive with the AI
/// review step; this record is the part that exists today, and it keeps the
/// photo + edits so History can render the outfit later.
public struct CompletedChallenge: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let card: ChallengeCard
    public let photoID: String
    public let draft: EditDraft
    public let completedAt: Date

    public init(
        id: UUID = UUID(),
        card: ChallengeCard,
        photoID: String,
        draft: EditDraft,
        completedAt: Date
    ) {
        self.id = id
        self.card = card
        self.photoID = photoID
        self.draft = draft
        self.completedAt = completedAt
    }
}

public protocol CompletedChallengeStore: Sendable {
    func load() -> [CompletedChallenge]
    /// Ignores a completion for a day that already has one — FR-029 requires
    /// completing to be idempotent, so a repeated tap can never double up.
    func append(_ completion: CompletedChallenge)
    /// Drops every completion recorded on `date`. Used by the dev menu today;
    /// the same call is what an "undo completion" feature would need.
    func removeCompletions(on date: Date)
}

public extension CompletedChallengeStore {
    /// FR-012: one completed challenge per user-local calendar day.
    func hasCompletion(on date: Date, calendar: Calendar = .current) -> Bool {
        load().contains { calendar.isDate($0.completedAt, inSameDayAs: date) }
    }
}

// ponytail: UserDefaults JSON array; move to SwiftData when History needs
// querying and paging.
public final class UserDefaultsCompletedChallengeStore: CompletedChallengeStore, @unchecked Sendable {
    // @unchecked: UserDefaults is documented thread-safe.
    private let defaults: UserDefaults
    private let calendar: Calendar
    private static let key = "completedChallenges"

    public init(defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.defaults = defaults
        self.calendar = calendar
    }

    public func load() -> [CompletedChallenge] {
        guard let data = defaults.data(forKey: Self.key) else { return [] }
        return (try? JSONDecoder().decode([CompletedChallenge].self, from: data)) ?? []
    }

    public func append(_ completion: CompletedChallenge) {
        var completions = load()
        guard !completions.contains(where: {
            calendar.isDate($0.completedAt, inSameDayAs: completion.completedAt)
        }) else {
            return // already completed that day
        }
        completions.append(completion)
        save(completions)
    }

    public func removeCompletions(on date: Date) {
        let kept = load().filter { !calendar.isDate($0.completedAt, inSameDayAs: date) }
        save(kept)
    }

    private func save(_ completions: [CompletedChallenge]) {
        guard let data = try? JSONEncoder().encode(completions) else {
            Log.report(AppError.unexpected)
            return
        }
        defaults.set(data, forKey: Self.key)
    }
}
