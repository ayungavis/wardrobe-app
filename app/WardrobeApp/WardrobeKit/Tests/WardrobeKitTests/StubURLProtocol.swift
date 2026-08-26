import Foundation
import Synchronization

struct StubbedReply: Sendable {
    var status = 200
    var body = Data()
    var headers: [String: String] = [:]

    static func json(_ text: String, status: Int = 200) -> StubbedReply {
        StubbedReply(status: status, body: Data(text.utf8))
    }

    func with(header name: String, _ value: String) -> StubbedReply {
        var reply = self
        reply.headers[name] = value
        return reply
    }
}

struct RecordedRequest: Sendable {
    let path: String
    let query: String?
    let body: Data
    let authorization: String?
    let contentType: String?
}

struct StubServer: Sendable {
    let session: URLSession
    private let id: String

    init() {
        id = UUID().uuidString
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        configuration.httpAdditionalHeaders = [StubURLProtocol.header: id]
        session = URLSession(configuration: configuration)
    }

    func stub(_ path: String, _ replies: StubbedReply...) {
        StubURLProtocol.state.withLock { $0.replies[Route(server: id, path: path), default: []] += replies }
    }

    func fail(with error: URLError) {
        StubURLProtocol.state.withLock { $0.failures[id] = error }
    }

    var sent: [RecordedRequest] {
        StubURLProtocol.state.withLock { $0.sent[id] ?? [] }
    }

    func sent(to path: String) -> [RecordedRequest] {
        sent.filter { $0.path == path }
    }
}

struct Route: Hashable, Sendable {
    let server: String
    let path: String
}

final class StubURLProtocol: URLProtocol {
    struct State: Sendable {
        var replies: [Route: [StubbedReply]] = [:]
        var sent: [String: [RecordedRequest]] = [:]
        var failures: [String: URLError] = [:]
    }

    static let header = "X-Stub-Server"
    static let state = Mutex(State())

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url, let server = request.value(forHTTPHeaderField: Self.header) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let recorded = RecordedRequest(
            path: url.path(),
            query: URLComponents(url: url, resolvingAgainstBaseURL: false)?.query,
            body: Self.body(of: request),
            authorization: request.value(forHTTPHeaderField: "Authorization"),
            contentType: request.value(forHTTPHeaderField: "Content-Type")
        )

        let outcome: Result<StubbedReply, URLError> = Self.state.withLock { state in
            state.sent[server, default: []].append(recorded)
            if let failure = state.failures[server] {
                return .failure(failure)
            }

            let route = Route(server: server, path: recorded.path)
            guard var queued = state.replies[route], !queued.isEmpty else {
                return .success(StubbedReply(status: 404))
            }
            let next = queued.removeFirst()
            state.replies[route] = queued
            return .success(next)
        }

        switch outcome {
        case let .failure(error):
            client?.urlProtocol(self, didFailWithError: error)
        case let .success(reply):
            let response = HTTPURLResponse(
                url: url,
                statusCode: reply.status,
                httpVersion: "HTTP/1.1",
                headerFields: reply.headers
            )
            if let response {
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            }
            client?.urlProtocol(self, didLoad: reply.body)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}

    private static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else { return Data() }

        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
