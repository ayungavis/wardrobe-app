import Foundation
import Testing
@testable import WardrobeKit

private let base = URL(string: "https://stub.invalid")!

private struct ProbeDTO: Decodable, Sendable {
    let stampedAt: Date
}

private struct ProbeEndpoint: Endpoint {
    typealias Response = ProbeDTO

    var path: String {
        "probe"
    }
}

private func sut(_ server: StubServer, _ session: FakeSessionService) -> SessionedAPIClient {
    SessionedAPIClient(
        client: URLSessionAPIClient(baseURL: base, session: server.session),
        session: session
    )
}

private let ok = #"{"stampedAt":"2026-08-24T03:14:15Z"}"#
private let refused = #"{"error":{"code":"unauthenticated","message":"no"}}"#

struct AuthenticatedAPIClientTests {
    @Test func aRefusedTokenIsRefreshedOnceAndTheCallRetriedOnce() async throws {
        let server = StubServer()
        server.stub("/probe", .json(refused, status: 401), .json(ok))
        let session = FakeSessionService()
        session.tokensInOrder = ["stale", "fresh"]

        _ = try await sut(server, session).send(ProbeEndpoint())

        let sent = server.sent(to: "/probe")
        #expect(sent.count == 2, "one refusal, one retry")
        #expect(sent.map(\.authorization) == ["Bearer stale", "Bearer fresh"])
        #expect(session.refreshCount == 1, "a second refresh would revoke the family (T07)")
    }

    @Test func aTokenRefusedTwiceGivesUpInsteadOfLooping() async {
        let server = StubServer()
        server.stub("/probe", .json(refused, status: 401), .json(refused, status: 401))
        let session = FakeSessionService()
        session.tokensInOrder = ["stale", "fresh"]

        await #expect(throws: AppError.sessionExpired) {
            try await sut(server, session).send(ProbeEndpoint())
        }
        #expect(server.sent(to: "/probe").count == 2, "never a third attempt")
        #expect(session.refreshCount == 1)
    }

    @Test func aCallThatSucceedsNeverRefreshes() async throws {
        let server = StubServer()
        server.stub("/probe", .json(ok))
        let session = FakeSessionService()

        _ = try await sut(server, session).send(ProbeEndpoint())

        #expect(session.refreshCount == 0)
        #expect(server.sent(to: "/probe").count == 1)
    }

    @Test func aRejectionThatIsNotAuthIsNeverRetried() async {
        let server = StubServer()
        server.stub("/probe", .json(#"{"error":{"code":"conflict","message":"no"}}"#, status: 409))
        let session = FakeSessionService()

        await #expect(throws: AppError.conflict) {
            try await sut(server, session).send(ProbeEndpoint())
        }
        #expect(server.sent(to: "/probe").count == 1)
        #expect(session.refreshCount == 0)
    }
}
