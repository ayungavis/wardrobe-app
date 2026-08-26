import Foundation
import Testing
@testable import WardrobeKit

private let base = URL(string: "https://wardrobe.test")!

private func makeSUT(
    server: StubServer,
    identities: StoredAnonymousIdentityRepository = StoredAnonymousIdentityRepository(
        store: InMemorySecureStore()
    ),
    tokens: StoredSessionTokenRepository = StoredSessionTokenRepository(
        store: InMemorySecureStore()
    )
) -> ServerSessionService {
    ServerSessionService(
        client: URLSessionAPIClient(baseURL: base, session: server.session),
        identities: identities,
        tokens: tokens
    )
}

private func sessionJSON(
    accountID: UUID = .v7(),
    access: String = "access-1",
    refresh: String = "refresh-1",
    expiresIn: TimeInterval = 2_592_000
) -> StubbedReply {
    let expires = ISO8601.fractional.format(Date().addingTimeInterval(expiresIn))
    let refreshExpires = ISO8601.fractional.format(Date().addingTimeInterval(15_552_000))
    return .json(
        """
        {"accountId":"\(accountID.uuidString)","accessToken":"\(access)",
         "refreshToken":"\(refresh)","expiresAt":"\(expires)",
         "refreshExpiresAt":"\(refreshExpires)"}
        """
    )
}

private func decodedBody(_ recorded: RecordedRequest) -> [String: String] {
    let object = try? JSONSerialization.jsonObject(with: recorded.body) as? [String: Any]
    return (object ?? [:]).compactMapValues { $0 as? String }
}

struct AnonymousIdentityTests {
    @Test func theIdentityIsMintedOnceAndStable() throws {
        let server = StubServer()
        let identities = StoredAnonymousIdentityRepository(store: InMemorySecureStore())
        let sut = makeSUT(server: server, identities: identities)

        let first = try sut.identity()
        let second = try sut.identity()

        #expect(first == second)
        #expect(identities.load() == first)
    }

    @Test func aFreshInstallMintsANewOne() throws {
        let server = StubServer()
        let first = try makeSUT(server: server).identity()

        let second = try makeSUT(server: server).identity()

        #expect(first != second)
    }

    @Test func itIsTimeOrderedSoTheServerIndexesStayCompact() throws {
        let server = StubServer()
        let identity = try makeSUT(server: server).identity()

        let version = identity.uuidString.split(separator: "-")[2].first
        #expect(version == "7")
    }

    @Test func skippingSignInStillLeavesAnIdentityWhenTheServerIsUnreachable() async {
        let server = StubServer()
        let identities = StoredAnonymousIdentityRepository(store: InMemorySecureStore())
        server.fail(with: URLError(.notConnectedToInternet))
        let sut = makeSUT(server: server, identities: identities)

        await sut.start()

        #expect(identities.load() != nil)
    }
}

struct ServerSessionTests {
    @Test func bootstrapSendsTheKeychainIdentityAndKeepsWhatComesBack() async throws {
        let server = StubServer()
        let identities = StoredAnonymousIdentityRepository(store: InMemorySecureStore())
        let tokens = StoredSessionTokenRepository(store: InMemorySecureStore())
        let accountID = UUID.v7()
        server.stub("/v1/sessions/anonymous", sessionJSON(accountID: accountID))
        let sut = makeSUT(server: server, identities: identities, tokens: tokens)

        await sut.start()

        let sent = try #require(server.sent(to: "/v1/sessions/anonymous").first)
        #expect(decodedBody(sent)["deviceId"] == identities.load()?.uuidString)
        #expect(tokens.load()?.accountID == accountID)
        #expect(tokens.load()?.accessToken == "access-1")
    }

    @Test func aSecondLaunchReusesTheStoredTokenWithoutAskingTheServer() async throws {
        let server = StubServer()
        let tokens = StoredSessionTokenRepository(store: InMemorySecureStore())
        server.stub("/v1/sessions/anonymous", sessionJSON())
        let sut = makeSUT(server: server, tokens: tokens)
        await sut.start()

        let token = try await sut.accessToken()

        #expect(token == "access-1")
        #expect(server.sent.count == 1)
    }

    @Test func anExpiredTokenIsRefreshedWithTheRefreshToken() async throws {
        let server = StubServer()
        let tokens = StoredSessionTokenRepository(store: InMemorySecureStore())
        try tokens.save(SessionTokens(
            accountID: .v7(),
            accessToken: "stale",
            refreshToken: "refresh-0",
            expiresAt: Date().addingTimeInterval(-60),
            refreshExpiresAt: Date().addingTimeInterval(86400)
        ))
        server.stub("/v1/sessions/refresh", sessionJSON(access: "access-2"))
        let sut = makeSUT(server: server, tokens: tokens)

        let token = try await sut.accessToken()

        #expect(token == "access-2")
        let sent = try #require(server.sent(to: "/v1/sessions/refresh").first)
        #expect(decodedBody(sent)["refreshToken"] == "refresh-0")
    }

    /// T07 revokes the whole session family when a refresh token is presented
    /// twice, so a second concurrent refresh does not waste a call — it signs
    /// the user out.
    @Test func manyCallersWithAnExpiredTokenProduceExactlyOneRefresh() async throws {
        let server = StubServer()
        let tokens = StoredSessionTokenRepository(store: InMemorySecureStore())
        try tokens.save(SessionTokens(
            accountID: .v7(),
            accessToken: "stale",
            refreshToken: "refresh-0",
            expiresAt: Date().addingTimeInterval(-60),
            refreshExpiresAt: Date().addingTimeInterval(86400)
        ))
        server.stub("/v1/sessions/refresh", sessionJSON(access: "access-2"))
        let sut = makeSUT(server: server, tokens: tokens)

        await withTaskGroup(of: String?.self) { group in
            for _ in 0 ..< 8 {
                group.addTask { try? await sut.accessToken() }
            }
            for await token in group {
                #expect(token == "access-2")
            }
        }

        #expect(server.sent(to: "/v1/sessions/refresh").count == 1)
    }

    @Test func anExpiredRefreshTokenFallsBackToTheKeychainIdentity() async throws {
        let server = StubServer()
        let tokens = StoredSessionTokenRepository(store: InMemorySecureStore())
        try tokens.save(SessionTokens(
            accountID: .v7(),
            accessToken: "stale",
            refreshToken: "refresh-0",
            expiresAt: Date().addingTimeInterval(-60),
            refreshExpiresAt: Date().addingTimeInterval(-1)
        ))
        server.stub("/v1/sessions/anonymous", sessionJSON(access: "access-3"))
        let sut = makeSUT(server: server, tokens: tokens)

        let token = try await sut.accessToken()

        #expect(token == "access-3")
        #expect(server.sent(to: "/v1/sessions/refresh").isEmpty)
    }

    @Test func linkingSendsTheTokenTheNonceAndTheDevice() async throws {
        let server = StubServer()
        let identities = StoredAnonymousIdentityRepository(store: InMemorySecureStore())
        let tokens = StoredSessionTokenRepository(store: InMemorySecureStore())
        let accountID = UUID.v7()
        server.stub("/v1/sessions/apple", sessionJSON(accountID: accountID))
        let sut = makeSUT(server: server, identities: identities, tokens: tokens)

        let linked = try await sut.linkApple(identityToken: "a.jwt.value", nonce: "raw-nonce")

        #expect(linked == accountID)
        let sent = try #require(server.sent(to: "/v1/sessions/apple").first)
        let body = decodedBody(sent)
        #expect(body["identityToken"] == "a.jwt.value")
        #expect(body["nonce"] == "raw-nonce")
        #expect(body["deviceId"] == identities.load()?.uuidString)
        #expect(tokens.load()?.accountID == accountID)
    }

    @Test func signingOutDropsTheTokensAndKeepsTheIdentity() async throws {
        let server = StubServer()
        let identities = StoredAnonymousIdentityRepository(store: InMemorySecureStore())
        let tokens = StoredSessionTokenRepository(store: InMemorySecureStore())
        server.stub("/v1/sessions/anonymous", sessionJSON())
        let sut = makeSUT(server: server, identities: identities, tokens: tokens)
        await sut.start()

        try await sut.signOut()

        #expect(tokens.load() == nil)
        #expect(identities.load() != nil)
    }
}
