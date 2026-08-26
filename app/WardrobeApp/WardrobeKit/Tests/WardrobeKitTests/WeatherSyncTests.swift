import CoreLocation
import Foundation
import Testing
@testable import WardrobeKit

@MainActor
final class FakeLocationService: LocationService {
    var permission: LocationPermission
    private(set) var permissionRequests = 0
    private(set) var locationRequests = 0

    init(permission: LocationPermission) {
        self.permission = permission
    }

    func requestPermission() async -> LocationPermission {
        permissionRequests += 1
        permission = .authorized
        return permission
    }

    func currentLocation() async throws -> CLLocation {
        locationRequests += 1
        return CLLocation(latitude: -6.2, longitude: 106.8)
    }
}

final class FakeForecastService: ForecastService, @unchecked Sendable {
    var days: [DayForecast]
    private(set) var calls = 0

    init(days: [DayForecast]) {
        self.days = days
    }

    func dailyForecast(at _: CLLocation) async throws -> [DayForecast] {
        calls += 1
        return days
    }
}

@MainActor
struct WeatherSyncTests {
    private let jakarta = TimeZone(identifier: "Asia/Jakarta") ?? .gmt

    private func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = jakarta
        return calendar
    }

    private func today() -> Date {
        calendar().date(from: DateComponents(year: 2026, month: 8, day: 26, hour: 8)) ?? .distantPast
    }

    private func tomorrow(condition: String, high: Double, low: Double) -> DayForecast {
        DayForecast(
            date: calendar().date(from: DateComponents(year: 2026, month: 8, day: 27, hour: 12))
                ?? .distantPast,
            condition: condition,
            highCelsius: high,
            lowCelsius: low
        )
    }

    private struct Harness {
        let sut: ForecastWeatherRepository
        let location: FakeLocationService
        let forecast: FakeForecastService
        let outbox: any OutboxRepository
    }

    private func makeSUT(
        permission: LocationPermission = .authorized,
        days: [DayForecast]? = nil
    ) -> Harness {
        let location = FakeLocationService(permission: permission)
        let forecast = FakeForecastService(days: days ?? [tomorrow(condition: "rain", high: 31.4, low: 23.6)])
        let outbox = StoredOutboxRepository(store: InMemoryOutboxStore())
        let defaults = UserDefaults(suiteName: "weather-\(UUID().uuidString)") ?? .standard
        let sut = ForecastWeatherRepository(
            location: location,
            weather: forecast,
            outbox: outbox,
            defaults: defaults,
            calendar: calendar()
        )
        return Harness(sut: sut, location: location, forecast: forecast, outbox: outbox)
    }

    private func contexts(_ outbox: any OutboxRepository) throws -> [OutboxEnvelope] {
        try outbox.entries().filter { $0.name == "upsertChallengeContext" }
    }

    @Test func aFirstSummaryIsStoredAndQueuedOnce() async throws {
        let harness = makeSUT()
        let sut = harness.sut
        let outbox = harness.outbox

        await sut.refresh(now: today())

        #expect(sut.lastSummary()?.localDate == "2026-08-27")
        #expect(sut.lastSummary()?.condition == "rain")
        #expect(try contexts(outbox).count == 1)
    }

    @Test func highAndLowAreRoundedWholeCelsius() async {
        let harness = makeSUT()
        let sut = harness.sut

        await sut.refresh(now: today())

        #expect(sut.lastSummary()?.highC == 31)
        #expect(sut.lastSummary()?.lowC == 24, "23.6 rounds up; truncating would report a colder night")
    }

    @Test func anUnchangedSummaryIsNotQueuedAgain() async throws {
        let harness = makeSUT()
        let sut = harness.sut
        let outbox = harness.outbox

        await sut.refresh(now: today())
        await sut.refresh(now: today().addingTimeInterval(60))

        #expect(try contexts(outbox).count == 1,
                "a day of foregrounding must not flood the outbox with identical context")
    }

    @Test func anUnchangedContextIsQueuedAgainAfterTheOutboxDrains() async throws {
        let harness = makeSUT()
        let sut = harness.sut
        let outbox = harness.outbox

        await sut.refresh(now: today())
        for entry in try contexts(outbox) {
            try outbox.acknowledge(id: entry.id)
        }
        await sut.refresh(now: today())

        let queued = try contexts(outbox).count
        #expect(
            queued == 1,
            "a dev reset mints a new account while zone and locale stay identical; suppressing the resend strands it"
        )
    }

    @Test func aChangedSummaryReplacesTheQueuedOne() async throws {
        let harness = makeSUT()
        let sut = harness.sut
        let forecast = harness.forecast
        let outbox = harness.outbox

        await sut.refresh(now: today())
        forecast.days = [tomorrow(condition: "clear", high: 33, low: 25)]
        await sut.refresh(now: today().addingTimeInterval(7 * 60 * 60))

        let queued = try contexts(outbox)
        #expect(queued.count == 1, "enqueueReplacing keeps one entry: it carries whole state")
        let payload = try #require(
            try JSONSerialization.jsonObject(with: queued[0].payload) as? [String: Any]
        )
        let weather = try #require(payload["weather"] as? [String: Any])
        #expect(weather["condition"] as? String == "clear")
    }

    @Test func aDeniedLocationStillSyncsTheZoneButNoWeather() async throws {
        let harness = makeSUT(permission: .denied)
        let sut = harness.sut
        let forecast = harness.forecast
        let outbox = harness.outbox

        await sut.refresh(now: today())

        #expect(forecast.calls == 0)
        #expect(sut.lastSummary() == nil)

        let queued = try #require(try contexts(outbox).first)
        let payload = try #require(
            try JSONSerialization.jsonObject(with: queued.payload) as? [String: Any]
        )
        #expect(payload["timeZone"] as? String == "Asia/Jakarta",
                "without a zone the server can never queue this account a deck at all")
        #expect(payload["weather"] == nil,
                "declining location costs the weather, not the whole feature")
    }

    @Test func refreshNeverRequestsPermissionItself() async {
        let harness = makeSUT(permission: .notDetermined)
        let sut = harness.sut
        let location = harness.location

        await sut.refresh(now: today())

        #expect(location.permissionRequests == 0,
                "the opt-in is contextual and belongs to a screen, never to a background refresh")
    }

    @Test func aForecastWithoutTomorrowYieldsNoSummary() async throws {
        let stale = DayForecast(
            date: calendar().date(from: DateComponents(year: 2026, month: 8, day: 25)) ?? .distantPast,
            condition: "clear",
            highCelsius: 30,
            lowCelsius: 24
        )
        let harness = makeSUT(days: [stale])
        let sut = harness.sut
        let outbox = harness.outbox

        await sut.refresh(now: today())

        #expect(sut.lastSummary() == nil,
                "sending nothing beats sending a summary stamped with the wrong day")

        let queued = try #require(try contexts(outbox).first)
        let payload = try #require(
            try JSONSerialization.jsonObject(with: queued.payload) as? [String: Any]
        )
        #expect(payload["weather"] == nil, "a forecast for the wrong day is not sent at all")
        #expect(payload["timeZone"] as? String == "Asia/Jakarta",
                "the zone is reported regardless: it is what lets the server queue a deck")
    }

    @Test func noCoordinateReachesTheOutboxPayload() async throws {
        let harness = makeSUT()
        let sut = harness.sut
        let outbox = harness.outbox

        await sut.refresh(now: today())

        let queued = try #require(try contexts(outbox).first)
        let payload = try #require(
            try JSONSerialization.jsonObject(with: queued.payload) as? [String: Any]
        )
        #expect(Set(payload.keys) == ["timeZone", "locale", "weather"])
        let weather = try #require(payload["weather"] as? [String: Any])
        #expect(
            Set(weather.keys) == ["localDate", "condition", "highC", "lowC"],
            "no latitude, no longitude, no accuracy, no timestamp: only the answer is synced"
        )
    }
}
