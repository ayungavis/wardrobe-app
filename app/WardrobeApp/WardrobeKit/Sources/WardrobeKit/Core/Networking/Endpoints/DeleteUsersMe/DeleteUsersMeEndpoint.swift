/// DELETE /v1/users/me
struct DeleteUsersMeEndpoint: Endpoint {
    typealias Response = DeleteUsersMeResponseDTO

    var path: String {
        "v1/users/me"
    }

    var method: HTTPMethod {
        .delete
    }
}
