import CoreGraphics
import Foundation

public struct CropSpec: Codable, Equatable, Sendable {
    public var rect: CGRect

    public init(rect: CGRect) {
        self.rect = rect
    }
}
