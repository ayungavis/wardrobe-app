import Foundation

public protocol SessionTokenRepository: Sendable {
    func load() -> SessionTokens?
    func save(_ tokens: SessionTokens) throws
    func clear() throws
}

public struct StoredSessionTokenRepository: SessionTokenRepository {
    private static let key = "sessionTokens"

    private let store: SecureStore

    public init(store: SecureStore = KeychainSecureStore()) {
        self.store = store
    }

    public func load() -> SessionTokens? {
        store.load(SessionTokens.self, forKey: Self.key)
    }

    public func save(_ tokens: SessionTokens) throws {
        try store.save(tokens, forKey: Self.key)
    }

    public func clear() throws {
        try store.clear(Self.key)
    }
}
