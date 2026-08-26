import Foundation

enum TomorrowForecast {
    static func summary(
        from days: [DayForecast],
        timeZone: TimeZone,
        now: Date,
        calendar: Calendar = .current
    ) -> WeatherSummary? {
        var zoned = calendar
        zoned.timeZone = timeZone
        guard let tomorrow = zoned.date(byAdding: .day, value: 1, to: now) else { return nil }
        let wanted = zoned.startOfDay(for: tomorrow)
        guard let forecast = days.first(where: { zoned.isDate($0.date, inSameDayAs: wanted) }) else {
            return nil
        }

        return WeatherSummary(
            localDate: LocalDay.string(from: wanted, timeZone: timeZone),
            timeZone: timeZone.identifier,
            condition: condition(forecast.condition),
            highC: Int(forecast.highCelsius.rounded()),
            lowC: Int(forecast.lowCelsius.rounded())
        )
    }

    static func condition(_ raw: String) -> String {
        let lowered = raw.lowercased()
        let vocabulary: [(needles: [String], word: String)] = [
            (["thunder", "hurricane", "tropicalstorm", "storm"], "storm"),
            (["snow", "sleet", "flurr", "blizzard", "hail", "wintry"], "snow"),
            (["rain", "drizzle", "shower"], "rain"),
            (["fog", "haze", "smoky"], "fog"),
            (["wind", "breezy", "blustery"], "wind"),
            (["hot"], "hot"),
            (["frigid", "cold"], "cold"),
            (["cloud", "overcast"], "cloudy"),
            (["clear", "sun", "fair"], "clear"),
        ]
        for entry in vocabulary where entry.needles.contains(where: lowered.contains) {
            return entry.word
        }
        return "cloudy"
    }
}
