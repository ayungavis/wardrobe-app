import Foundation

public protocol CompletedChallengeRepository: Sendable {
    func load() -> [CompletedChallenge]
    /// Ignores a completion for a day that already has one — FR-029 requires
    /// completing to be idempotent, so a repeated tap can never double up.
    func append(_ completion: CompletedChallenge)
    /// Drops every completion recorded on `date`. Used by the dev menu today;
    /// the same call is what an "undo completion" feature would need.
    func removeCompletions(on date: Date)
}

public extension CompletedChallengeRepository {
    /// FR-012: one completed challenge per user-local calendar day.
    func hasCompletion(on date: Date, calendar: Calendar = .current) -> Bool {
        load().contains { calendar.isDate($0.completedAt, inSameDayAs: date) }
    }
}

// ponytail: UserDefaults JSON array; move to SwiftData when History needs
// querying and paging.
public final class UserDefaultsCompletedChallengeRepository: CompletedChallengeRepository, @unchecked Sendable {
    // @unchecked: UserDefaults is documented thread-safe.
    private let defaults: UserDefaults
    private let calendar: Calendar
    private static let key = "completedChallenges"

    public init(defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.defaults = defaults
        self.calendar = calendar
    }

    /// Decoded one entry at a time on purpose. Decoding the array in one go
    /// means a single unreadable completion takes the **whole history** with
    /// it — and `append` then writes the truncated array straight back over
    /// the original, permanently. Per entry, one bad record costs one record.
    ///
    /// ponytail: a skipped entry is dropped rather than preserved verbatim.
    /// Keeping its raw JSON needs a passthrough type; it comes back from the
    /// server once sync exists, and the server is the system of record for
    /// confirmed documents (FR-096).
    public func load() -> [CompletedChallenge] {
        guard let data = defaults.data(forKey: Self.key) else { return [] }
        guard let entries = try? JSONDecoder().decode([LenientEntry<CompletedChallenge>].self, from: data) else {
            Log.report(AppError.unexpected)
            return []
        }

        let completions = entries.compactMap(\.value)
        if completions.count != entries.count {
            Log.report(AppError.unexpected)
        }
        return completions
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

/// Decodes what it can and reports `nil` for what it cannot, so one unreadable
/// element cannot fail the array around it.
private struct LenientEntry<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}
