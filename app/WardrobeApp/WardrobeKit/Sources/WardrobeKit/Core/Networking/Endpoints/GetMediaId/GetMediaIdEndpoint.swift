import Foundation

/// GET /v1/media/{id}
struct GetMediaIdEndpoint: Endpoint {
    typealias Response = GetMediaIdResponseDTO

    let id: UUID

    var path: String {
        "v1/media/\(id.uuidString.lowercased())"
    }
}
