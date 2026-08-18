import Foundation

public protocol ActiveChallengeRepository: Sendable {
    func load() -> ActiveChallenge?
    func save(_ challenge: ActiveChallenge)
    func clear()
}

// ponytail: UserDefaults JSON blob; migrate to SwiftData when history lands.
public final class UserDefaultsActiveChallengeRepository: ActiveChallengeRepository, @unchecked Sendable {
    // @unchecked: UserDefaults is documented thread-safe.
    private let defaults: UserDefaults
    private static let key = "activeChallenge"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> ActiveChallenge? {
        guard let data = defaults.data(forKey: Self.key) else { return nil }
        do {
            return try JSONDecoder().decode(ActiveChallenge.self, from: data)
        } catch {
            // Reported rather than swallowed: a challenge written by a newer
            // app throws `documentFromNewerApp`, and returning a silent nil
            // makes an in-progress challenge look like it never existed.
            Log.report(error)
            return nil
        }
    }

    public func save(_ challenge: ActiveChallenge) {
        guard let data = try? JSONEncoder().encode(challenge) else {
            Log.report(AppError.unexpected)
            return
        }
        defaults.set(data, forKey: Self.key)
    }

    public func clear() {
        defaults.removeObject(forKey: Self.key)
    }
}
