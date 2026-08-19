import CoreGraphics

public struct GarmentSegmentation: Sendable {
    public let classMap: [[Int]]
    public let image: CGImage

    public init(classMap: [[Int]], image: CGImage) {
        self.classMap = classMap
        self.image = image
    }
}
