import CoreGraphics

/// A repaired, normalized garment image and how much its mask could be trusted.
public struct GarmentCutout: Sendable {
    public let image: CGImage
    public let maskQuality: Float
}
