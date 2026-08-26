import Foundation

/// GET /v1/changes
struct GetChangesEndpoint: Endpoint {
    typealias Response = GetChangesResponseDTO

    let since: Int64
    let limit: Int

    var path: String {
        "v1/changes"
    }

    var queryItems: [URLQueryItem] {
        [
            URLQueryItem(name: "since", value: String(since)),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
    }
}
