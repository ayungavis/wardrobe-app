/// GET /v1/whoami
struct GetWhoamiEndpoint: Endpoint {
    typealias Response = GetWhoamiResponseDTO

    var path: String {
        "v1/whoami"
    }
}
