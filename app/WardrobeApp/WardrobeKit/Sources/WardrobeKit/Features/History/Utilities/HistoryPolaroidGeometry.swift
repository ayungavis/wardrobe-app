import CoreGraphics

/// Where the print's window and its lip sit inside a History card.
///
/// Every number is a fraction of the **card's width**, so one card works at any
/// size — the grid draws it at about 164 points and the detail screen at 345.
///
/// The ratios are not invented: they are the original Figma frame's paddings
/// (170.06 × 312.01, window inset 6.7 from the sides) carried over. What
/// changed is the window's shape — it now matches the story canvas the user
/// actually composed on, so nothing of their work is cropped away, and the card
/// grew taller to make room rather than the picture shrinking to fit.
enum HistoryPolaroidGeometry {
    /// Equal on three sides, the way a print's border runs.
    static let padding: CGFloat = 6.7 / 170.06
    /// The fat bottom lip, where the date is printed.
    static let bottomLip: CGFloat = 60.74 / 170.06

    static let windowWidth: CGFloat = 1 - padding * 2
    static let windowHeight: CGFloat = windowWidth / StoryCanvas.aspectRatio

    /// Width ÷ height, for `.aspectRatio`.
    static var cardAspectRatio: CGFloat {
        1 / (padding + windowHeight + bottomLip)
    }
}
