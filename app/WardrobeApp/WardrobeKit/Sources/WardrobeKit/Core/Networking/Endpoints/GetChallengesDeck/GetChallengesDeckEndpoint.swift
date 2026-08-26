import Foundation

/// GET /v1/challenges/deck
struct GetChallengesDeckEndpoint: Endpoint {
    typealias Response = GetChallengesDeckResponseDTO

    let localDate: String
    let locale: String

    var path: String {
        "v1/challenges/deck"
    }

    var queryItems: [URLQueryItem] {
        [
            URLQueryItem(name: "localDate", value: localDate),
            URLQueryItem(name: "locale", value: locale),
        ]
    }
}
