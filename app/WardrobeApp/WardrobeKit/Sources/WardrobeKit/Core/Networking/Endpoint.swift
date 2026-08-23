import Foundation

public enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
}

public protocol Endpoint: Sendable {
    associatedtype Response: Decodable & Sendable

    var path: String { get }
    var method: HTTPMethod { get }
    var accessToken: String? { get }
}

public extension Endpoint {
    var method: HTTPMethod {
        .get
    }

    var accessToken: String? {
        nil
    }
}

public protocol RequestEndpoint: Endpoint {
    associatedtype Request: Encodable & Sendable

    var request: Request { get }
}
