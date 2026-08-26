/// DELETE /v1/sessions/current
struct DeleteSessionsCurrentEndpoint: Endpoint {
    typealias Response = DeleteSessionsCurrentResponseDTO

    var path: String {
        "v1/sessions/current"
    }

    var method: HTTPMethod {
        .delete
    }
}
