import Foundation
import Testing
@testable import WardrobeKit

private let healthBase = URL(string: "https://stub.invalid")!

@MainActor
struct DevMenuSessionTests {
    private func makeSUT(
        session: FakeSessionService = FakeSessionService(),
        client: any AuthenticatedAPIClient = StubAuthenticatedClient(),
        plainClient: any APIClient = URLSessionAPIClient(baseURL: healthBase, session: StubServer().session),
        tokens: SessionTokenRepository = StoredSessionTokenRepository(store: InMemorySecureStore())
    ) -> DevMenuViewModel {
        DevMenuViewModel(
            activeRepository: InMemoryActiveChallengeRepository(),
            completedRepository: InMemoryCompletedChallengeRepository(),
            photoRepository: SpyPhotoRepository(),
            wardrobeRepository: InMemoryWardrobeItemRepository(),
            thumbnails: InMemoryGarmentThumbnailRepository(),
            previews: InMemoryCompletionPreviewRepository(),
            onboarding: OnboardingModel(
                preferences: InMemoryAccountPreferencesRepository(),
                accounts: StoredAppleAccountRepository(store: InMemorySecureStore()),
                session: FakeSessionService()
            ),
            session: session,
            client: client,
            plainClient: plainClient,
            baseURL: healthBase,
            tokens: tokens,
            outboxRepository: StoredOutboxRepository(store: InMemoryOutboxStore()),
            feed: ServerChangeFeedRepository(client: StubAuthenticatedClient(), cursor: InMemoryCursorStore()),
            coordinator: ServerSyncCoordinator(
                client: StubAuthenticatedClient(),
                outbox: StoredOutboxRepository(store: InMemoryOutboxStore()),
                feed: ServerChangeFeedRepository(client: StubAuthenticatedClient(), cursor: InMemoryCursorStore())
            ),
            diagnosticsStore: InMemoryDiagnosticsStore(),
            media: ServerMediaRepository(
                client: StubAuthenticatedClient(), cache: InMemoryMediaCacheStore()
            )
        )
    }

    private func storedTokens(accountID: UUID = UUID()) -> SessionTokenRepository {
        let tokens = StoredSessionTokenRepository(store: InMemorySecureStore())
        try? tokens.save(SessionTokens(
            accountID: accountID,
            accessToken: "access",
            refreshToken: "refresh",
            expiresAt: Date().addingTimeInterval(3600),
            refreshExpiresAt: Date().addingTimeInterval(86400)
        ))
        return tokens
    }

    @Test func loadingTheSessionReportsWhatIsStoredWithoutCallingTheServer() async {
        let client = StubAuthenticatedClient()
        let accountID = UUID()
        let sut = makeSUT(client: client, tokens: storedTokens(accountID: accountID))

        sut.loadSession()
        await sut.sessionTask?.value

        guard case let .loaded(info) = sut.sessionState else {
            Issue.record("expected a loaded session, got \(sut.sessionState)")
            return
        }
        #expect(info.accountID == accountID)
        #expect(info.isAccessUsable)
        #expect(info.whoami == nil)
        #expect(client.callCount == 0, "reload must not spend a request")
    }

    @Test func callingWhoamiGoesThroughTheAuthenticatedClient() async {
        let client = StubAuthenticatedClient()
        let accountID = UUID()
        client.whoamiAccountID = accountID
        let sut = makeSUT(client: client, tokens: storedTokens(accountID: accountID))

        sut.loadSession(callingWhoami: true)
        await sut.sessionTask?.value

        guard case let .loaded(info) = sut.sessionState else {
            Issue.record("expected a loaded session, got \(sut.sessionState)")
            return
        }
        #expect(client.callCount == 1)
        #expect(info.whoami?.accountID == accountID, "the server agrees with the stored account")
    }

    @Test func aRefusedWhoamiLandsAsFailedRatherThanCrashing() async {
        let client = StubAuthenticatedClient()
        client.error = .sessionExpired
        let sut = makeSUT(client: client, tokens: storedTokens())

        sut.loadSession(callingWhoami: true)
        await sut.sessionTask?.value

        #expect(sut.sessionState == .failed(.sessionExpired))
    }

    @Test func aSecondLoadCancelsTheOneStillInFlight() async {
        let sut = makeSUT(tokens: storedTokens())

        sut.loadSession()
        let stale = sut.sessionTask
        sut.loadSession()

        #expect(stale?.isCancelled == true)
        await sut.sessionTask?.value
    }

    // MARK: Reachability

    @Test func aReachableServerReportsItsStatus() async {
        let server = StubServer()
        server.stub("/health", .json(#"{"status":"ok"}"#))
        let sut = makeSUT(
            plainClient: URLSessionAPIClient(baseURL: healthBase, session: server.session)
        )

        sut.checkHealth()
        await sut.healthTask?.value

        #expect(sut.healthState == .loaded("ok"))
    }

    @Test func anUnreachableServerLandsAsANetworkFailure() async {
        let server = StubServer()
        server.fail(with: URLError(.cannotConnectToHost))
        let sut = makeSUT(
            plainClient: URLSessionAPIClient(baseURL: healthBase, session: server.session)
        )

        sut.checkHealth()
        await sut.healthTask?.value

        #expect(sut.healthState == .failed(.network))
    }

    @Test func theHealthCheckNeverAsksForAToken() async {
        let session = FakeSessionService()
        session.tokenError = .sessionExpired
        let server = StubServer()
        server.stub("/health", .json(#"{"status":"ok"}"#))
        let sut = makeSUT(
            session: session,
            plainClient: URLSessionAPIClient(baseURL: healthBase, session: server.session)
        )

        sut.checkHealth()
        await sut.healthTask?.value

        #expect(sut.healthState == .loaded("ok"), "a check that needs a token cannot diagnose a dead server")
    }
}
