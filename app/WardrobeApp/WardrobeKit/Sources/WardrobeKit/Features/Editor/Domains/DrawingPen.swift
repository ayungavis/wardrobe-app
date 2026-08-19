import Foundation

public struct DrawingPen: Equatable, Sendable {
    public var color: DrawingColor
    public var width: DrawingWidth
    public var isErasing: Bool

    public init(color: DrawingColor = .black, width: DrawingWidth = .medium, isErasing: Bool = false) {
        self.color = color
        self.width = width
        self.isErasing = isErasing
    }
}
