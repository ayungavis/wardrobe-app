import Foundation

#if canImport(WeatherKit)
    import WeatherKit
#endif

extension AppContainer {
    static func defaultWeatherRepository() -> any WeatherRepository {
        ForecastWeatherRepository(
            location: defaultLocationService(),
            weather: defaultForecastService(),
            outbox: makeOutboxRepository()
        )
    }

    private static func defaultLocationService() -> any LocationService {
        #if os(iOS)
            CoreLocationService()
        #else
            DeniedLocationService()
        #endif
    }

    private static func defaultForecastService() -> any ForecastService {
        #if canImport(WeatherKit)
            AppleForecastService()
        #else
            UnavailableForecastService()
        #endif
    }
}
