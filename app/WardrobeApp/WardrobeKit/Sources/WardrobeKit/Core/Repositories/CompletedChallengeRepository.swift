import Foundation

public protocol CompletedChallengeRepository: Sendable {
    func load() -> [CompletedChallenge]
    func append(_ completion: CompletedChallenge)
    func removeCompletions(on date: Date)
    func removeAll()
}

public extension CompletedChallengeRepository {
    func hasCompletion(on date: Date, calendar: Calendar = .current) -> Bool {
        load().contains { calendar.isDate($0.completedAt, inSameDayAs: date) }
    }
}

// ponytail: UserDefaults JSON array; move to SwiftData when History needs
// querying and paging.
// Type safety: @unchecked because UserDefaults and Calendar are both immutable
// here and UserDefaults is itself thread-safe; the type holds no mutable state.
public final class UserDefaultsCompletedChallengeRepository: CompletedChallengeRepository, @unchecked Sendable {
    private let defaults: UserDefaults
    private let calendar: Calendar
    private static let key = "completedChallenges"

    public init(defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.defaults = defaults
        self.calendar = calendar
    }

    // ponytail: a skipped entry is dropped rather than preserved verbatim.
    // Keeping its raw JSON needs a passthrough type; it comes back from the
    // server once sync exists, and the server is the system of record for
    // confirmed documents (FR-096).
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
        completions.append(completion)
        save(completions)
    }

    public func removeCompletions(on date: Date) {
        let kept = load().filter { !calendar.isDate($0.completedAt, inSameDayAs: date) }
        save(kept)
    }

    public func removeAll() {
        defaults.removeObject(forKey: Self.key)
    }

    private func save(_ completions: [CompletedChallenge]) {
        guard let data = try? JSONEncoder().encode(completions) else {
            Log.report(AppError.unexpected)
            return
        }
        defaults.set(data, forKey: Self.key)
    }
}

private struct LenientEntry<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}
