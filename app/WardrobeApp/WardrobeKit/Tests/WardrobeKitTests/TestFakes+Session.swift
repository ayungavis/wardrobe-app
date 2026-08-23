import Foundation
@testable import WardrobeKit

final class InMemorySecureStore: SecureStore, @unchecked Sendable {
    // @unchecked: tests drive it from one actor at a time.
    var saveError: AppError?
    private var stored: [String: Data] = [:]

    func load<Value: Decodable>(_ type: Value.Type, forKey key: String) -> Value? {
        stored[key].flatMap { try? JSONDecoder().decode(type, from: $0) }
    }

    func save(_ value: some Encodable, forKey key: String) throws {
        if let saveError {
            throw saveError
        }
        stored[key] = try JSONEncoder().encode(value)
    }

    func clear(_ key: String) throws {
        stored[key] = nil
    }
}

final class FakeSessionService: SessionService, @unchecked Sendable {
    // @unchecked: tests drive it from one actor at a time.
    var deviceID = UUID.v7()
    var linkedAccountID = UUID.v7()
    var linkError: AppError?
    private(set) var linkedWith: (identityToken: String, nonce: String)?
    private(set) var signedOut = false
    private(set) var startCount = 0

    func identity() throws -> UUID {
        deviceID
    }

    func start() async {
        startCount += 1
    }

    func accessToken() async throws -> String {
        "access"
    }

    func linkApple(identityToken: String, nonce: String) async throws -> UUID {
        linkedWith = (identityToken, nonce)
        if let linkError {
            throw linkError
        }
        return linkedAccountID
    }

    func signOut() async throws {
        signedOut = true
    }
}
