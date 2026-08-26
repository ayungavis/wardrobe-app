import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import WardrobeKit

private func jpeg(stamped: String?, offset: String? = nil) -> Data {
    let pixels = CGContext(
        data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    )
    let image = pixels?.makeImage()

    let output = NSMutableData()
    let destination = CGImageDestinationCreateWithData(
        output, UTType.jpeg.identifier as CFString, 1, nil
    )
    var properties: [CFString: Any] = [:]
    if let stamped {
        var exif: [CFString: Any] = [kCGImagePropertyExifDateTimeOriginal: stamped]
        if let offset {
            exif[kCGImagePropertyExifOffsetTimeOriginal] = offset
        }
        properties[kCGImagePropertyExifDictionary] = exif
    }
    if let destination, let image {
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        CGImageDestinationFinalize(destination)
    }
    return output as Data
}

struct CaptureDateTests {
    @Test func aPhotoCarriesTheDayItWasTaken() throws {
        let taken = try #require(CaptureDate.original(in: jpeg(stamped: "2024:03:15 10:30:00")))

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        #expect(calendar.dateComponents([.year, .month, .day], from: taken).year == 2024)
        #expect(calendar.dateComponents([.year, .month, .day], from: taken).month == 3)
        #expect(calendar.dateComponents([.year, .month, .day], from: taken).day == 15)
    }

    @Test func theRecordedOffsetDecidesTheInstant() throws {
        let jakarta = try #require(
            CaptureDate.original(in: jpeg(stamped: "2024:03:15 10:30:00", offset: "+07:00"))
        )
        let london = try #require(
            CaptureDate.original(in: jpeg(stamped: "2024:03:15 10:30:00", offset: "+00:00"))
        )

        #expect(london.timeIntervalSince(jakarta) == 7 * 3600)
    }

    @Test func aPhotoWithoutACaptureDateResolvesToNothing() {
        #expect(CaptureDate.original(in: jpeg(stamped: nil)) == nil)
        #expect(CaptureDate.original(in: Data([0x01, 0x02, 0x03])) == nil)
    }

    /// The bug this ticket fixes: absent metadata must never become today.
    @Test func absentMetadataIsNeverQuietlyReplacedByToday() {
        #expect(CaptureDate.original(in: jpeg(stamped: nil)) == nil)
        #expect(CaptureDate.instant("not a stamp", offset: nil) == nil)
    }
}
