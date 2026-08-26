import Foundation

public protocol AuthenticatedAPIClient: Sendable {
    func send<Route: Endpoint>(_ endpoint: Route) async throws -> Route.Response
    func send<Route: RequestEndpoint>(_ endpoint: Route) async throws -> Route.Response
}

public struct SessionedAPIClient: AuthenticatedAPIClient {
    private let client: any APIClient
    private let session: any SessionService

    public init(client: any APIClient, session: any SessionService) {
        self.client = client
        self.session = session
    }

    public func send<Route: Endpoint>(_ endpoint: Route) async throws -> Route.Response {
        try await authorised { try await client.send(endpoint, authorization: $0) }
    }

    public func send<Route: RequestEndpoint>(_ endpoint: Route) async throws -> Route.Response {
        try await authorised { try await client.send(endpoint, authorization: $0) }
    }

    // ponytail: one retry, never a loop. T07 revokes the whole session family when
    // a refresh token is replayed, so a second refresh signs the user out rather
    // than merely wasting a call.
    private func authorised<Value>(
        _ call: (String) async throws -> Value
    ) async throws -> Value {
        do {
            return try await call(session.accessToken())
        } catch AppError.sessionExpired {
            try Task.checkCancellation()
            return try await call(session.refreshedAccessToken())
        }
    }
}
