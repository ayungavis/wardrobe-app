import Foundation

public protocol AnonymousIdentityRepository: Sendable {
    func load() -> UUID?
    func save(_ identity: UUID) throws
}

public struct StoredAnonymousIdentityRepository: AnonymousIdentityRepository {
    private static let key = "anonymousIdentity"

    private let store: SecureStore

    public init(store: SecureStore = KeychainSecureStore()) {
        self.store = store
    }

    public func load() -> UUID? {
        store.load(UUID.self, forKey: Self.key)
    }

    public func save(_ identity: UUID) throws {
        try store.save(identity, forKey: Self.key)
    }
}
