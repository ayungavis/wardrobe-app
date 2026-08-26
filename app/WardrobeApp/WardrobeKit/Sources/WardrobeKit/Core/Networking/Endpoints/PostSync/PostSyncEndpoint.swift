import Foundation

/// POST /v1/sync
struct PostSyncEndpoint: RequestEndpoint {
    typealias Response = PostSyncResponseDTO

    let request: PostSyncRequestDTO

    var path: String {
        "v1/sync"
    }

    var method: HTTPMethod {
        .post
    }
}
