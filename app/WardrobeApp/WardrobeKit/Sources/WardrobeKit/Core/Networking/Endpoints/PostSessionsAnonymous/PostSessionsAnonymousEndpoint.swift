import Foundation

/// POST /v1/sessions/anonymous
struct PostSessionsAnonymousEndpoint: RequestEndpoint {
    typealias Response = PostSessionsAnonymousResponseDTO

    let request: PostSessionsAnonymousRequestDTO

    var path: String {
        "v1/sessions/anonymous"
    }

    var method: HTTPMethod {
        .post
    }
}
