import CoreGraphics

enum CameraZoom {
    static let presets: [CGFloat] = [0.5, 1, 2]
    static let standard: CGFloat = 1

    static func clamp(_ factor: CGFloat, to options: [CGFloat]) -> CGFloat {
        guard let low = options.first, let high = options.last else { return factor }
        return min(high, max(low, factor))
    }
}
