import Foundation

/// POST /v1/media
struct PostMediaEndpoint: RequestEndpoint {
    typealias Response = PostMediaResponseDTO

    let request: PostMediaRequestDTO

    var path: String {
        "v1/media"
    }

    var method: HTTPMethod {
        .post
    }
}
