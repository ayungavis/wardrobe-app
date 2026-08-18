import CoreGraphics
import Foundation

/// Visible rect in unit image space (all components 0...1).
public struct CropSpec: Codable, Equatable, Sendable {
    public var rect: CGRect

    public init(rect: CGRect) {
        self.rect = rect
    }
}
