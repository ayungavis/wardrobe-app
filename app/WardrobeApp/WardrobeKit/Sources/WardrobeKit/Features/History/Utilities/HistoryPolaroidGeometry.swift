import CoreGraphics

enum HistoryPolaroidGeometry {
    static let padding: CGFloat = 6.7 / 170.06
    static let bottomLip: CGFloat = 60.74 / 170.06

    static let windowWidth: CGFloat = 1 - padding * 2
    static let windowHeight: CGFloat = windowWidth / StoryCanvas.aspectRatio

    static var cardAspectRatio: CGFloat {
        1 / (padding + windowHeight + bottomLip)
    }
}
