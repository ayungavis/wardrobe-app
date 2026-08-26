import Foundation

@MainActor
public protocol WeatherRepository: AnyObject, Sendable {
    var permission: LocationPermission { get }
    func lastSummary() -> WeatherSummary?
    func requestPermission() async
    func refresh(now: Date) async
}

@MainActor
public final class ForecastWeatherRepository: WeatherRepository {
    private let location: any LocationService
    private let weather: any ForecastService
    private let outbox: (any OutboxRepository)?
    private let defaults: UserDefaults
    private let calendar: Calendar
    private static let key = "weatherSummary"
    private static let fetchedAtKey = "weatherFetchedAt"
    private static let sentKey = "challengeContextSent"
    // ponytail: a forecast for tomorrow is re-asked at most every six hours.
    // Tune it against how often WeatherKit actually revises a daily forecast.
    private static let refetchAfter: TimeInterval = 6 * 60 * 60

    public init(
        location: any LocationService,
        weather: any ForecastService,
        outbox: (any OutboxRepository)? = nil,
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current
    ) {
        self.location = location
        self.weather = weather
        self.outbox = outbox
        self.defaults = defaults
        self.calendar = calendar
    }

    public var permission: LocationPermission {
        location.permission
    }

    public func lastSummary() -> WeatherSummary? {
        guard let data = defaults.data(forKey: Self.key) else { return nil }
        return try? JSONDecoder().decode(WeatherSummary.self, from: data)
    }

    public func requestPermission() async {
        _ = await location.requestPermission()
    }

    public func refresh(now: Date) async {
        let timeZone = calendar.timeZone
        guard location.permission == .authorized else {
            queue(nil, at: now)
            return
        }
        let wanted = LocalDay.string(
            from: calendar.date(byAdding: .day, value: 1, to: now) ?? now,
            timeZone: timeZone
        )
        let fetchedAt = defaults.object(forKey: Self.fetchedAtKey) as? Date
        let covered = lastSummary().map {
            $0.localDate == wanted && $0.timeZone == timeZone.identifier
        } ?? false
        let recent = fetchedAt.map { now.timeIntervalSince($0) < Self.refetchAfter } ?? false
        if covered, recent {
            return
        }

        do {
            let forecast = try await weather.dailyForecast(at: location.currentLocation())
            guard let summary = TomorrowForecast.summary(
                from: forecast,
                timeZone: timeZone,
                now: now,
                calendar: calendar
            ) else { return }
            defaults.set(now, forKey: Self.fetchedAtKey)
            guard summary != lastSummary() else { return }
            defaults.set(try? JSONEncoder().encode(summary), forKey: Self.key)
            queue(summary, at: now)
        } catch {
            Log.report(error, logger: Log.network)
        }
    }

    // ponytail: UserDefaults, so the summary write and the outbox entry are two
    // steps rather than one transaction — the same gap account preferences
    // carry. A lost summary self-heals on the next foreground.
    private func queue(_ summary: WeatherSummary?, at date: Date) {
        let args = UpsertChallengeContextArgsDTO(
            timeZone: summary?.timeZone ?? calendar.timeZone.identifier,
            locale: Locale.current.identifier,
            weather: summary.map { summary in
                ChallengeWeatherArgsDTO(
                    localDate: summary.localDate,
                    condition: summary.condition,
                    highC: summary.highC,
                    lowC: summary.lowC
                )
            }
        )
        guard args.signature != defaults.string(forKey: Self.sentKey) else { return }
        defaults.set(args.signature, forKey: Self.sentKey)
        do {
            try outbox?.enqueueReplacing(
                SyncMutation.upsertChallengeContext(args).queued(),
                at: date
            )
        } catch {
            Log.report(error)
        }
    }
}
