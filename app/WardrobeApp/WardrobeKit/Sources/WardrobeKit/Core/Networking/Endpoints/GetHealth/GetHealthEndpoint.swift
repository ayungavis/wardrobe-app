/// GET /health
struct GetHealthEndpoint: Endpoint {
    typealias Response = GetHealthResponseDTO

    var path: String {
        "health"
    }
}
