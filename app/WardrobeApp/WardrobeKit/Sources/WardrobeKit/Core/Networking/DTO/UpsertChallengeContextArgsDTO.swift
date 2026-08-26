import Foundation

struct UpsertChallengeContextArgsDTO: Encodable, Sendable {
    let timeZone: String
    let locale: String?
    let weather: ChallengeWeatherArgsDTO?
}

struct ChallengeWeatherArgsDTO: Encodable, Sendable {
    let localDate: String
    let condition: String
    let highC: Int
    let lowC: Int
}
