import Foundation
import Testing
@testable import WardrobeKit

private let base = URL(string: "https://wardrobe.test")!

private func client(_ server: StubServer) -> URLSessionAPIClient {
    URLSessionAPIClient(baseURL: base, session: server.session)
}

private struct ProbeDTO: Decodable, Sendable {
    let stampedAt: Date
}

private struct ProbeEndpoint: Endpoint {
    typealias Response = ProbeDTO

    var path: String {
        "probe"
    }

    var accessToken: String?
}

private struct ProbeRequestDTO: Encodable, Sendable {
    let nonce: String
}

private struct PostProbeEndpoint: RequestEndpoint {
    typealias Response = ProbeDTO

    let request: ProbeRequestDTO

    var path: String {
        "probe"
    }

    var method: HTTPMethod {
        .post
    }
}

struct APIClientTests {
    @Test func fractionalSecondsDecodeBecauseThatIsWhatTheServerSends() async throws {
        let server = StubServer()
        server.stub("/probe", .json(#"{"stampedAt":"2026-08-24T03:14:15.926535897Z"}"#))

        let probe = try await client(server).send(ProbeEndpoint())

        #expect(abs(probe.stampedAt.timeIntervalSince1970 - 1_787_541_255.926) < 0.01)
    }

    @Test func aWholeSecondInstantDecodesToo() async throws {
        let server = StubServer()
        server.stub("/probe", .json(#"{"stampedAt":"2026-08-24T03:14:15Z"}"#))

        let probe = try await client(server).send(ProbeEndpoint())

        #expect(probe.stampedAt.timeIntervalSince1970 == 1_787_541_255)
    }

    @Test func anUnauthenticatedEnvelopeBecomesASessionError() async {
        let server = StubServer()
        server.stub(
            "/probe",
            .json(#"{"error":{"code":"unauthenticated","message":"nope"}}"#, status: 401)
        )

        await #expect(throws: AppError.sessionExpired) {
            try await client(server).send(ProbeEndpoint())
        }
    }

    @Test func anUnavailableDependencyReadsAsANetworkProblem() async {
        let server = StubServer()
        server.stub(
            "/probe",
            .json(#"{"error":{"code":"unavailable","message":"down"}}"#, status: 503)
        )

        await #expect(throws: AppError.network) {
            try await client(server).send(ProbeEndpoint())
        }
    }

    @Test func anyOtherRejectionIsSeparateFromAnOfflineDevice() async {
        let server = StubServer()
        server.stub(
            "/probe",
            .json(#"{"error":{"code":"bad_request","message":"no"}}"#, status: 400)
        )

        await #expect(throws: AppError.serverRejected) {
            try await client(server).send(ProbeEndpoint())
        }
    }

    @Test func aFailureBodyIsNeverDecodedAsSuccess() async {
        let server = StubServer()
        server.stub("/probe", .json(#"{"stampedAt":"2026-08-24T03:14:15Z"}"#, status: 500))

        await #expect(throws: AppError.serverRejected) {
            try await client(server).send(ProbeEndpoint())
        }
    }

    @Test func anOfflineDeviceIsANetworkError() async {
        let server = StubServer()
        server.fail(with: URLError(.notConnectedToInternet))

        await #expect(throws: AppError.network) {
            try await client(server).send(ProbeEndpoint())
        }
    }

    @Test func anEndpointWithNoRequestSendsNoBodyAtAll() async throws {
        let server = StubServer()
        server.stub("/probe", .json(#"{"stampedAt":"2026-08-24T03:14:15Z"}"#))

        _ = try await client(server).send(ProbeEndpoint())

        let sent = try #require(server.sent(to: "/probe").first)
        #expect(sent.body.isEmpty, "a GET that ships a JSON body is a request the server may refuse")
        #expect(sent.contentType == nil)
    }

    @Test func anEndpointWithARequestShipsExactlyItsDTO() async throws {
        let server = StubServer()
        server.stub("/probe", .json(#"{"stampedAt":"2026-08-24T03:14:15Z"}"#))

        _ = try await client(server).send(
            PostProbeEndpoint(request: ProbeRequestDTO(nonce: "raw-nonce"))
        )

        let sent = try #require(server.sent(to: "/probe").first)
        #expect(String(bytes: sent.body, encoding: .utf8) == #"{"nonce":"raw-nonce"}"#)
        #expect(sent.contentType == "application/json")
    }

    @Test func anAccessTokenTravelsAsABearerHeader() async throws {
        let server = StubServer()
        server.stub("/probe", .json(#"{"stampedAt":"2026-08-24T03:14:15Z"}"#))

        _ = try await client(server).send(ProbeEndpoint(accessToken: "tok"))

        let sent = try #require(server.sent(to: "/probe").first)
        #expect(sent.authorization == "Bearer tok")
    }
}

struct SignInNonceTests {
    @Test func hashingMatchesTheServerSpelling() {
        #expect(
            SignInNonce.hashed("a-client-generated-nonce")
                == "6a264878f1535f17aff4db3feda236163ac2e1fd1b7d9374772d5228b458a0eb"
        )
    }

    @Test func everyNonceIsDifferent() {
        let server = StubServer()
        let nonces = Set((0 ..< 32).map { _ in SignInNonce.make() })

        #expect(nonces.count == 32)
        #expect(nonces.allSatisfy { $0.count == 64 })
    }
}

struct UUIDv7Tests {
    @Test func theVersionNibbleSaysSeven() {
        let server = StubServer()
        let identity = UUID.v7()

        #expect(identity.uuidString.split(separator: "-")[2].first == "7")
    }

    @Test func laterIdentitiesSortAfterEarlierOnes() {
        let server = StubServer()
        let earlier = UUID.v7(at: Date(timeIntervalSince1970: 1_000_000))
        let later = UUID.v7(at: Date(timeIntervalSince1970: 2_000_000))

        #expect(earlier.uuidString < later.uuidString)
    }

    @Test func theVariantBitsStayRFC4122() {
        let server = StubServer()
        let identity = UUID.v7()

        let variant = identity.uuidString.lowercased().split(separator: "-")[3].first
        #expect("89ab".contains(variant ?? " "))
    }
}
