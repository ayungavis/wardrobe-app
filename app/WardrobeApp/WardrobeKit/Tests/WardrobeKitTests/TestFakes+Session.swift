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
    private(set) var refreshCount = 0
    var tokensInOrder: [String] = ["access"]
    var tokenError: AppError?

    func identity() throws -> UUID {
        deviceID
    }

    func start() async {
        startCount += 1
    }

    func accessToken() async throws -> String {
        if let tokenError {
            throw tokenError
        }
        return tokensInOrder.first ?? "access"
    }

    func refreshedAccessToken() async throws -> String {
        refreshCount += 1
        if tokensInOrder.count > 1 {
            tokensInOrder.removeFirst()
        }
        return tokensInOrder.first ?? "access"
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

final class StubAuthenticatedClient: AuthenticatedAPIClient, @unchecked Sendable {
    // @unchecked: tests drive it from one actor at a time.
    var whoamiAccountID = UUID()
    var whoamiSessionID = UUID()
    var error: AppError?
    private(set) var callCount = 0

    func send<Route: Endpoint>(_: Route) async throws -> Route.Response {
        try reply()
    }

    func send<Route: RequestEndpoint>(_: Route) async throws -> Route.Response {
        try reply()
    }

    private func reply<Value: Decodable>() throws -> Value {
        callCount += 1
        if let error {
            throw error
        }
        let json = """
        {"accountId":"\(whoamiAccountID.uuidString)","sessionId":"\(whoamiSessionID.uuidString)"}
        """
        return try JSONDecoder.api.decode(Value.self, from: Data(json.utf8))
    }
}
