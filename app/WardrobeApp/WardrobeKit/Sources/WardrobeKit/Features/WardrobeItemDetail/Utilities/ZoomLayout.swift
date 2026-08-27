import CoreGraphics

enum ZoomLayout {
    struct Insets: Equatable {
        let horizontal: CGFloat
        let vertical: CGFloat
    }

    static func fitted(in bounds: CGSize, margin: CGFloat) -> CGSize {
        CGSize(
            width: max(0, bounds.width - margin * 2),
            height: max(0, bounds.height - margin * 2)
        )
    }

    static func centring(bounds: CGSize, content: CGSize) -> Insets {
        Insets(
            horizontal: max(0, bounds.width - content.width) / 2,
            vertical: max(0, bounds.height - content.height) / 2
        )
    }
}
