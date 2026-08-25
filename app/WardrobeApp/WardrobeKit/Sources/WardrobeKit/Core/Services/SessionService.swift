import Foundation

public protocol SessionService: Sendable {
    func identity() throws -> UUID
    func start() async
    func accessToken() async throws -> String
    func refreshedAccessToken() async throws -> String
    func linkApple(identityToken: String, nonce: String) async throws -> UUID
    func signOut() async throws
}

public actor ServerSessionService: SessionService {
    private let client: APIClient
    private let identities: AnonymousIdentityRepository
    private let tokens: SessionTokenRepository
    private var inFlight: Task<SessionTokens, Error>?

    public init(
        client: APIClient,
        identities: AnonymousIdentityRepository,
        tokens: SessionTokenRepository
    ) {
        self.client = client
        self.identities = identities
        self.tokens = tokens
    }

    public nonisolated func identity() throws -> UUID {
        try Self.mint(from: identities)
    }

    public func start() async {
        do {
            _ = try await accessToken()
        } catch is CancellationError {
        } catch {
            Log.network.info("no server session yet: \(String(describing: AppError(wrapping: error)))")
        }
    }

    public func accessToken() async throws -> String {
        if let stored = tokens.load(), stored.isUsable(at: .now) {
            return stored.accessToken
        }
        return try await claim().accessToken
    }

    public func refreshedAccessToken() async throws -> String {
        try await claim().accessToken
    }

    public func linkApple(identityToken: String, nonce: String) async throws -> UUID {
        let endpoint = try PostSessionsAppleEndpoint(
            request: PostSessionsAppleRequestDTO(
                deviceId: identity(), identityToken: identityToken, nonce: nonce
            )
        )
        let session = try await Self.tokens(from: client.send(endpoint))
        try tokens.save(session)
        return session.accountID
    }

    public func signOut() async throws {
        inFlight?.cancel()
        inFlight = nil
        try tokens.clear()
    }

    private func claim() async throws -> SessionTokens {
        if let running = inFlight {
            return try await running.value
        }

        let work = Task { [client, identities, tokens] in
            let stored = tokens.load()
            let session: SessionTokens
            if let stored, stored.canRefresh(at: .now) {
                let endpoint = PostSessionsRefreshEndpoint(
                    request: PostSessionsRefreshRequestDTO(refreshToken: stored.refreshToken)
                )
                session = try await Self.tokens(from: client.send(endpoint))
            } else {
                let endpoint = try PostSessionsAnonymousEndpoint(
                    request: PostSessionsAnonymousRequestDTO(
                        deviceId: Self.mint(from: identities)
                    )
                )
                session = try await Self.tokens(from: client.send(endpoint))
            }
            try tokens.save(session)
            return session
        }

        inFlight = work
        defer { inFlight = nil }
        return try await work.value
    }

    private static func tokens(from response: SessionResponseDTO) -> SessionTokens {
        SessionTokens(
            accountID: response.accountId,
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            expiresAt: response.expiresAt,
            refreshExpiresAt: response.refreshExpiresAt
        )
    }

    private static func mint(from identities: AnonymousIdentityRepository) throws -> UUID {
        if let existing = identities.load() {
            return existing
        }
        let minted = UUID.v7()
        try identities.save(minted)
        return minted
    }
}
