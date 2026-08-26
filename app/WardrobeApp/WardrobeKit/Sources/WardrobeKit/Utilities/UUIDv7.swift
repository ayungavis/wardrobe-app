import Foundation

public extension UUID {
    static func v7(at instant: Date = .now) -> UUID {
        var bytes = UUID().uuid
        let milliseconds = UInt64((instant.timeIntervalSince1970 * 1000).rounded())
        bytes.0 = UInt8(truncatingIfNeeded: milliseconds >> 40)
        bytes.1 = UInt8(truncatingIfNeeded: milliseconds >> 32)
        bytes.2 = UInt8(truncatingIfNeeded: milliseconds >> 24)
        bytes.3 = UInt8(truncatingIfNeeded: milliseconds >> 16)
        bytes.4 = UInt8(truncatingIfNeeded: milliseconds >> 8)
        bytes.5 = UInt8(truncatingIfNeeded: milliseconds)
        bytes.6 = (bytes.6 & 0x0F) | 0x70
        return UUID(uuid: bytes)
    }
}
