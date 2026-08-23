import Foundation

/// POST /v1/sessions/apple
struct PostSessionsAppleEndpoint: RequestEndpoint {
    typealias Response = PostSessionsAppleResponseDTO

    let request: PostSessionsAppleRequestDTO

    var path: String {
        "v1/sessions/apple"
    }

    var method: HTTPMethod {
        .post
    }
}
