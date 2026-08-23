import Foundation

public protocol APIClient: Sendable {
    func send<Route: Endpoint>(_ endpoint: Route) async throws -> Route.Response
    func send<Route: RequestEndpoint>(_ endpoint: Route) async throws -> Route.Response
}

public struct URLSessionAPIClient: APIClient {
    private let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    public func send<Route: Endpoint>(_ endpoint: Route) async throws -> Route.Response {
        try await perform(endpoint, body: nil)
    }

    public func send<Route: RequestEndpoint>(_ endpoint: Route) async throws -> Route.Response {
        try await perform(endpoint, body: JSONEncoder.api.encode(endpoint.request))
    }

    private func perform<Route: Endpoint>(
        _ endpoint: Route,
        body: Data?
    ) async throws -> Route.Response {
        let (data, response) = try await transfer(endpoint, body: body)

        guard let http = response as? HTTPURLResponse else { throw AppError.network }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw Self.failure(status: http.statusCode, body: data)
        }

        do {
            return try JSONDecoder.api.decode(Route.Response.self, from: data)
        } catch {
            Log.report(error)
            throw AppError.serverRejected
        }
    }

    private func transfer(
        _ endpoint: some Endpoint,
        body: Data?
    ) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: baseURL.appending(path: endpoint.path))
        request.httpMethod = endpoint.method.rawValue
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let accessToken = endpoint.accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }

        do {
            return try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw AppError(wrapping: error)
        }
    }

    static func failure(status: Int, body: Data) -> AppError {
        let envelope = try? JSONDecoder.api.decode(ErrorEnvelopeDTO.self, from: body)
        if envelope?.error.code == "unauthenticated" || status == 401 {
            return .sessionExpired
        }
        return status == 503 ? .network : .serverRejected
    }
}
