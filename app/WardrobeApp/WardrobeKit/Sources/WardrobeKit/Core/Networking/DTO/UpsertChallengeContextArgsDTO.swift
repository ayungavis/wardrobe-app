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

extension UpsertChallengeContextArgsDTO {
    var signature: String {
        let weather = weather.map { "\($0.localDate)|\($0.condition)|\($0.highC)|\($0.lowC)" } ?? "-"
        return "\(timeZone)|\(locale ?? "-")|\(weather)"
    }
}
