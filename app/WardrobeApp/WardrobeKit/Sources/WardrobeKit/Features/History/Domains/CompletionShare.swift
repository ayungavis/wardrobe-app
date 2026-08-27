import CoreGraphics
import Foundation

public struct CompletionShare: Equatable, Sendable {
    public let url: URL
    public let qr: CGImage

    public init(url: URL, qr: CGImage) {
        self.url = url
        self.qr = qr
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.url == rhs.url && lhs.qr === rhs.qr
    }
}
