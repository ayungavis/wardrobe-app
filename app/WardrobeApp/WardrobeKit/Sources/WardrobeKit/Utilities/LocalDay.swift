import Foundation

enum LocalDay {
    static func string(from date: Date, timeZone: TimeZone = .current) -> String {
        var style = Date.ISO8601FormatStyle(timeZone: timeZone)
        style = style.year().month().day().dateSeparator(.dash)
        return date.formatted(style)
    }
}
