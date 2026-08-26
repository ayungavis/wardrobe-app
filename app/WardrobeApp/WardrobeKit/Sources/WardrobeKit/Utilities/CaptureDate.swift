import Foundation
import ImageIO

public enum CaptureDate {
    public static func original(in data: Data) -> Date? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
              as? [CFString: Any],
              let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let stamped = exif[kCGImagePropertyExifDateTimeOriginal] as? String
        else {
            return nil
        }
        return instant(stamped, offset: exif[kCGImagePropertyExifOffsetTimeOriginal] as? String)
    }

    static func instant(_ stamped: String, offset: String?) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        // ponytail: without OffsetTimeOriginal the stamp is local time with no
        // zone, so the device's current one is the only guess available. It is
        // why FR-048 makes the date visible and correctable.
        formatter.timeZone = offset.flatMap(zone) ?? .current
        return formatter.date(from: stamped)
    }

    private static func zone(_ offset: String) -> TimeZone? {
        let digits = offset.filter(\.isNumber)
        guard digits.count == 4,
              let hours = Int(digits.prefix(2)),
              let minutes = Int(digits.suffix(2))
        else {
            return nil
        }
        let seconds = (hours * 3600) + (minutes * 60)
        return TimeZone(secondsFromGMT: offset.hasPrefix("-") ? -seconds : seconds)
    }
}
