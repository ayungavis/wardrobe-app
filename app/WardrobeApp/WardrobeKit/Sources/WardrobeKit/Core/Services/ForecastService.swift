import CoreLocation
import Foundation

public struct DayForecast: Equatable, Sendable {
    public let date: Date
    public let condition: String
    public let highCelsius: Double
    public let lowCelsius: Double

    public init(date: Date, condition: String, highCelsius: Double, lowCelsius: Double) {
        self.date = date
        self.condition = condition
        self.highCelsius = highCelsius
        self.lowCelsius = lowCelsius
    }
}

public protocol ForecastService: Sendable {
    func dailyForecast(at location: CLLocation) async throws -> [DayForecast]
}

public struct UnavailableForecastService: ForecastService {
    public init() {}

    public func dailyForecast(at _: CLLocation) async throws -> [DayForecast] {
        throw AppError.unavailable
    }
}

#if canImport(WeatherKit)
    import WeatherKit

    public struct AppleForecastService: ForecastService {
        public init() {}

        public func dailyForecast(at location: CLLocation) async throws -> [DayForecast] {
            let forecast = try await WeatherKit.WeatherService.shared.weather(
                for: location,
                including: .daily
            )
            return forecast.forecast.map { day in
                DayForecast(
                    date: day.date,
                    condition: String(describing: day.condition),
                    highCelsius: day.highTemperature.converted(to: .celsius).value,
                    lowCelsius: day.lowTemperature.converted(to: .celsius).value
                )
            }
        }
    }
#endif
