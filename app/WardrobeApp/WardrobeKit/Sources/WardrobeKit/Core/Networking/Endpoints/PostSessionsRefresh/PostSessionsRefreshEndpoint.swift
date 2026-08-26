import Foundation

/// POST /v1/sessions/refresh
struct PostSessionsRefreshEndpoint: RequestEndpoint {
    typealias Response = PostSessionsRefreshResponseDTO

    let request: PostSessionsRefreshRequestDTO

    var path: String {
        "v1/sessions/refresh"
    }

    var method: HTTPMethod {
        .post
    }
}
