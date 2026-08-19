import Foundation

/// What the drawing tool is currently set to.
///
/// Session state, not document state: it describes the hand, not the picture.
/// It outlives one drawing session so returning to the tool finds it as you
/// left it, and it is never stored — FR-099 names the three preferences that
/// follow the account, and this is not one of them.
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
