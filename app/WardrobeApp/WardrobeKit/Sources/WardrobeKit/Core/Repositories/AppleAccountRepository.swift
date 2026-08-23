import Foundation

public protocol AppleAccountRepository: Sendable {
    func load() -> AppleAccount?
    func save(_ account: AppleAccount) throws
    func clear() throws
}

public struct StoredAppleAccountRepository: AppleAccountRepository {
    private static let key = "appleAccount"

    private let store: SecureStore

    public init(store: SecureStore = KeychainSecureStore()) {
        self.store = store
    }

    public func load() -> AppleAccount? {
        store.load(AppleAccount.self, forKey: Self.key)
    }

    public func save(_ account: AppleAccount) throws {
        try store.save(load().map { $0.merged(with: account) } ?? account, forKey: Self.key)
    }

    public func clear() throws {
        try store.clear(Self.key)
    }
}
