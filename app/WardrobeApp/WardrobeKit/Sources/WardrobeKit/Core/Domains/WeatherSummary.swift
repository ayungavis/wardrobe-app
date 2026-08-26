import Foundation

public struct WeatherSummary: Codable, Equatable, Sendable {
    public let localDate: String
    public let timeZone: String
    public let condition: String
    public let highC: Int
    public let lowC: Int

    public init(localDate: String, timeZone: String, condition: String, highC: Int, lowC: Int) {
        self.localDate = localDate
        self.timeZone = timeZone
        self.condition = condition
        self.highC = highC
        self.lowC = lowC
    }
}
