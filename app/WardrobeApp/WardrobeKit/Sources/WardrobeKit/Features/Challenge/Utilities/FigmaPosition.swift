import Foundation

struct FigmaPosition {
    let x: CGFloat // fraction 0-1, relative to its container
    let y: CGFloat
    let widthFraction: CGFloat
    let heightFraction: CGFloat
    let rotation: Double // degrees, 0 if none

    init(
        figmaX: CGFloat,
        figmaY: CGFloat,
        figmaWidth: CGFloat,
        figmaHeight: CGFloat,
        frameWidth: CGFloat,
        frameHeight: CGFloat,
        rotation: Double = 0
    ) {
        x = (figmaX + figmaWidth / 2) / frameWidth
        y = (figmaY + figmaHeight / 2) / frameHeight
        widthFraction = figmaWidth / frameWidth
        heightFraction = figmaHeight / frameHeight
        self.rotation = rotation
    }
}
