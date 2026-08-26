import Foundation

struct StickerPlacement: Identifiable {
    let id = UUID()
    let imageName: String
    let x: CGFloat
    let y: CGFloat
    let widthFraction: CGFloat
    let heightFraction: CGFloat
    let rotation: Double

    init(
        _ imageName: String,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat = 0,
        rotation: Double = 0
    ) {
        self.imageName = imageName
        self.x = x
        self.y = y
        widthFraction = width
        heightFraction = height
        self.rotation = rotation
    }

    init(
        _ imageName: String,
        figmaX: CGFloat,
        figmaY: CGFloat,
        figmaWidth: CGFloat,
        figmaHeight: CGFloat,
        frameWidth: CGFloat,
        frameHeight: CGFloat,
        rotation: Double = 0
    ) {
        self.imageName = imageName
        x = (figmaX + figmaWidth / 2) / frameWidth
        y = (figmaY + figmaHeight / 2) / frameHeight
        widthFraction = figmaWidth / frameWidth
        heightFraction = figmaHeight / frameHeight
        self.rotation = rotation
    }
}
