import CoreGraphics

/// Zoom presets, in display space. `0.5` needs an ultra-wide lens, so each
/// service filters this list down to what its device supports.
enum CameraZoom {
    static let presets: [CGFloat] = [0.5, 1, 2]
    static let standard: CGFloat = 1

    static func clamp(_ factor: CGFloat, to options: [CGFloat]) -> CGFloat {
        guard let low = options.first, let high = options.last else { return factor }
        return min(high, max(low, factor))
    }
}
