import Foundation
import Testing
@testable import WardrobeKit

struct LocalDayTests {
    private static let jakarta = TimeZone(identifier: "Asia/Jakarta") ?? .gmt

    private func morning() -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.jakarta
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 27
        components.hour = 6
        return calendar.date(from: components) ?? .distantPast
    }

    @Test func anEarlyMorningStillBelongsToItsOwnLocalDay() {
        #expect(
            LocalDay.string(from: morning(), timeZone: Self.jakarta) == "2026-08-27",
            "UTC+7 mornings fall on the previous UTC day, so a GMT format style dates the deck one day early"
        )
    }

    @Test func theSameInstantIsAnEarlierDayFurtherWest() {
        let losAngeles = TimeZone(identifier: "America/Los_Angeles") ?? .gmt
        #expect(LocalDay.string(from: morning(), timeZone: losAngeles) == "2026-08-26")
    }
}
