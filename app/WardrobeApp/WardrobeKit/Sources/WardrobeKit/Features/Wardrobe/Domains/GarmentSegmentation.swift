import CoreGraphics

/// A per-pixel class map plus the upright photo it was computed from.
public struct GarmentSegmentation: Sendable {
    public let classMap: [[Int]]
    public let image: CGImage

    public init(classMap: [[Int]], image: CGImage) {
        self.classMap = classMap
        self.image = image
    }
}
