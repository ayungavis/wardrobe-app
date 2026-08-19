import Foundation

struct FigmaPosition {
    let x: CGFloat
    let y: CGFloat
    let widthFraction: CGFloat
    let heightFraction: CGFloat
    let rotation: Double

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
