import Foundation
import Security

public protocol AppleAccountRepository: Sendable {
    func load() -> AppleAccount?
    func save(_ account: AppleAccount) throws
    func clear() throws
}

public final class KeychainAppleAccountRepository: AppleAccountRepository, @unchecked Sendable {
    // @unchecked: the Keychain services are thread-safe, and nothing here is mutable.
    private let service: String
    private let account = "appleAccount"

    public init(service: String = Bundle.main.bundleIdentifier ?? "com.ayungavis.WardrobeApp") {
        self.service = service
    }

    public func load() -> AppleAccount? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else {
            return nil
        }
        return try? JSONDecoder().decode(AppleAccount.self, from: data)
    }

    public func save(_ account: AppleAccount) throws {
        let merged = load().map { $0.merged(with: account) } ?? account
        let data = try JSONEncoder().encode(merged)

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        guard status != errSecItemNotFound else {
            var insert = baseQuery
            insert.merge(attributes) { _, new in new }
            guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else {
                throw AppError.unexpected
            }
            return
        }
        guard status == errSecSuccess else { throw AppError.unexpected }
    }

    public func clear() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AppError.unexpected
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
