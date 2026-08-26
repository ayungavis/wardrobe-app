import Foundation
import Security

public protocol SecureStore: Sendable {
    func load<Value: Decodable>(_ type: Value.Type, forKey key: String) -> Value?
    func save(_ value: some Encodable, forKey key: String) throws
    func clear(_ key: String) throws
}

public struct KeychainSecureStore: SecureStore {
    private let service: String

    public init(service: String = Bundle.main.bundleIdentifier ?? "com.ayungavis.WardrobeApp") {
        self.service = service
    }

    public func load<Value: Decodable>(_ type: Value.Type, forKey key: String) -> Value? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else {
            return nil
        }
        return try? JSONDecoder().decode(type, from: data)
    }

    public func save(_ value: some Encodable, forKey key: String) throws {
        let data = try JSONEncoder().encode(value)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let status = SecItemUpdate(baseQuery(key) as CFDictionary, attributes as CFDictionary)
        guard status != errSecItemNotFound else {
            var insert = baseQuery(key)
            insert.merge(attributes) { _, new in new }
            guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else {
                throw AppError.unexpected
            }
            return
        }
        guard status == errSecSuccess else { throw AppError.unexpected }
    }

    public func clear(_ key: String) throws {
        let status = SecItemDelete(baseQuery(key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AppError.unexpected
        }
    }

    private func baseQuery(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }
}
