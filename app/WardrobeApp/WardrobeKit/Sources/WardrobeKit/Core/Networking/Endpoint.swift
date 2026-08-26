import Foundation

public enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
}

public protocol Endpoint: Sendable {
    associatedtype Response: Decodable & Sendable

    var path: String { get }
    var method: HTTPMethod { get }
    var queryItems: [URLQueryItem] { get }
}

public extension Endpoint {
    var method: HTTPMethod {
        .get
    }

    var queryItems: [URLQueryItem] {
        []
    }
}

public protocol RequestEndpoint: Endpoint {
    associatedtype Request: Encodable & Sendable

    var request: Request { get }
}
